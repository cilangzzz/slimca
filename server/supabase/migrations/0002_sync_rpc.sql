-- =============================================================================
-- Slimca 同步一期 RPC 迁移（W7-8，§11.1「托管 Supabase 接入+RLS+幂等；设备注册」）
-- 依据 docs/design/产品设计文档.md：
--   §6.2 架构与读写路径：
--     写路径 POST /rpc/sync_push（幂等键 = outbox.id）→ 服务端校验
--     （schema_ver / 行存在性 / hlc 单调）→ 签发权威 seq → 回执；
--     读路径 GET /rpc/sync_pull?since_hlc=…（per-table 游标）；
--     「op seq（BIGSERIAL）+ outbox.id 唯一键保证幂等（重试不重复入账）」。
--   §6.3 HLC 定宽编码（字典序=全序；13:6:12 段位）。
--   §6.4 schema 演进（行级 schema_ver 只加列前向兼容，超档拒绝）。
--   §6.5 冲突矩阵（服务端半边：墓碑拒绝复活、todos set 胜、LWW 后写者胜）。
--   §5.6⑰ devices（设备注册 RPC：幂等=刷新 last_seen）、§5.6⑯ sync_outbox
--     （服务端只留 outbox.id 作幂等键 → 0001 的 sync_ops 表）。
--   §6.1 原则 4 / §3.7 数据主权：服务端只承载同步真值，可整体迁出。
--
-- 三个 RPC（函数名与客户端 SupabaseSyncBackend 冻结命名一致）：
--   1. sync_push_batch(p_device_id, p_ops)     → {acks, rejections}
--   2. sync_pull_changes(p_device_id, p_cursors, p_limit)
--                                              → {changes, cursors, has_more}
--   3. register_device(p_device_id, ...)       → {device, server_now}
--
-- 设计决策（对照 0001_init.sql 的既定方案）：
--   A. SECURITY DEFINER + 自行按 auth.uid() 约束：0001 头注释第 8 条——RPC 以
--      definer 运行绕过 RLS 并自行承担服务端校验。所有语句显式带 user_id =
--      auth.uid()（含跨用户 id 占用拦截），杜绝越权读写；anon 无 JWT 时
--      auth.uid() 为 NULL，一律拒绝。
--   B. 幂等（§6.2）：sync_ops.outbox_id 唯一键（0001 已建）去重；命中即原回执
--      重放（revision=op_seq、acked_at）；并发重复由 ON CONFLICT DO NOTHING
--      兜底，后到者重放先到者的 op_seq——重试不重复入账。
--   C. 权威 revision（§6.2「签发权威 seq」）：接受即写 sync_ops 取
--      BIGSERIAL op_seq，并回写业务行 revision = op_seq；客户端 ack 后
--      本地回写同一值（§5.1 revision「同步升级为服务端版本」）。
--   D. 拒绝三分类回传（§6.2 校验清单，wire 值与客户端 SyncRejectionReason
--      逐一对齐）：schema_ver / row_missing / hlc_non_monotonic /
--      base_revision_conflict / tombstone_conflict / unknown——引擎侧按
--      「作废（drop+采纳服务端）/ 暂缓（保留重试）/ 幂等完成（drop）」处置。
--   E. 投递水位（双设备一致的关键补漏，§6.7「双端各 100 条一致率 100%」）：
--      只按「hlc > 客户端游标」增量会漏掉「他端离线迟到的低 hlc 新行」——
--      本迁移建 sync_pull_watermarks（per user/device/table 的 op_seq 水位），
--      pull 资格 = hlc > 客户端游标 OR revision > 投递水位。op_seq 是服务端
--      接受序（单调），任何在上一轮 pull 之后被接受/改写的行必然重新可见。
--   F. 列白名单防注入：动态 SQL 的列名全部来自 sync_table_registry.cols
--      （迁移时从 information_schema 按 0001 表结构生成，含 14 张同步真值表；
--      客户端 payload 键不进动态 SQL——jsonb_populate_record 自动忽略未知键，
--      正好实现 §6.4「老客户端忽略新列」的前向兼容对侧）。
--   G. todos set 胜合并（§6.5 第 6 行，0001 README 既定落点）：并发 set vs
--      unset → set 胜；「取消完成仅无并发时生效」以 baseRevision 命中服务端
--      现值（无并发）为判据，并发 unset 由服务端保留 done_at（勾选永不丢失）。
--   H. 设备吊销（§5.6⑰ revoked_at）：已吊销设备的 push/pull 一律拒绝
--      （一键下线的服务端半边）；未注册设备 MVP 期放行（注册与首推可乱序）。
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- ① sync_pull_watermarks —— 服务端 per-(user, device, table) 投递水位（E）
--    客户端对应：无 Drift 表（客户端游标 sync_cursors 是 hlc 水位，本表是
--    服务端投递簿的 op_seq 水位，两者是「双轨资格」的两半，见 pull RPC）
-- -----------------------------------------------------------------------------
CREATE TABLE sync_pull_watermarks (
  user_id     uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_id   TEXT NOT NULL,               -- = 客户端 device_id（§6.3 节点段同域）
  table_name  TEXT NOT NULL,               -- 同步真值表名（§5.1 冻结表集）
  last_op_seq BIGINT NOT NULL DEFAULT 0,   -- 本设备已投递到的最大权威 op_seq
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_id, table_name),
  CONSTRAINT sync_pull_watermarks_table_chk
    CHECK (table_name IN ('entries', 'entry_lines', 'food_items', 'ledgers',
                          'categories', 'budgets', 'todos', 'fitness_sessions',
                          'fitness_plans', 'exercise_sets', 'savings_goals',
                          'savings_contributions', 'corrections', 'theme_profiles'))
);

CREATE INDEX idx_sync_pull_watermarks_user_device
  ON sync_pull_watermarks (user_id, device_id);

-- RLS（§6.2「RLS 按 user_id 行级隔离」）：直接 REST 访问只限本主行；
-- RPC 走 SECURITY DEFINER 绕过并自行约束。
ALTER TABLE sync_pull_watermarks ENABLE ROW LEVEL SECURITY;
CREATE POLICY sync_pull_watermarks_owner_all ON sync_pull_watermarks
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- -----------------------------------------------------------------------------
-- ② sync_table_registry —— 同步表注册表（客户端 sync_table_catalog.dart 的
--    服务端镜像；W1 冻结表集，§5.1）
--    parent_table/parent_key/rank 与客户端 SyncTableSpec 一一对应：
--    - parent_table：push 的「行存在性」校验父表（corrections 为 NULL——审计
--      日志永可插入、不受跨表顺序影响，§5.6⑮）；
--    - rank：pull 输出依赖序（父表先于子表，§6.2）。
--    cols 在下方 DO 块从 information_schema 按 0001 实际表结构生成（单侧真值，
--    杜绝手写漂移）：白名单只用于服务端自身动态 SQL 的列名来源，客户端
--    payload 键不经白名单拼接（决策 F）。
-- -----------------------------------------------------------------------------
CREATE TABLE sync_table_registry (
  table_name   TEXT PRIMARY KEY,
  parent_table TEXT,
  parent_key   TEXT,
  rank         INTEGER NOT NULL DEFAULT 0,
  cols         TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO sync_table_registry (table_name, parent_table, parent_key, rank) VALUES
  ('entries',                NULL,               NULL,          0),
  ('ledgers',                NULL,               NULL,          0),
  ('categories',             NULL,               NULL,          0),
  ('budgets',                NULL,               NULL,          0),
  ('todos',                  NULL,               NULL,          0),
  ('fitness_sessions',       NULL,               NULL,          0),
  ('fitness_plans',          NULL,               NULL,          0),
  ('savings_goals',          NULL,               NULL,          0),
  ('theme_profiles',         NULL,               NULL,          0),
  ('entry_lines',            'entries',          'entry_id',    1),
  ('food_items',             'entries',          'entry_id',    2),
  ('exercise_sets',          'fitness_sessions', 'session_id',  1),
  ('savings_contributions',  'savings_goals',    'goal_id',     1),
  ('corrections',            NULL,               NULL,          1);

-- 按 0001_init.sql 的实际表结构生成列白名单：排除 user_id（服务端专用列，
-- 恒由 auth.uid() 签发，客户端 payload 不得指定——RLS 强化，见决策 A）。
DO $$
DECLARE
  v_missing integer;
BEGIN
  UPDATE sync_table_registry r
  SET cols = sub.cols
  FROM (
    SELECT c.table_name,
           array_agg(c.column_name ORDER BY c.ordinal_position) AS cols
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name IN (SELECT table_name FROM sync_table_registry)
      AND c.column_name <> 'user_id'
    GROUP BY c.table_name
  ) sub
  WHERE r.table_name = sub.table_name;

  -- 完整性断言：14 张表必须全部取到列清单（缺表说明 0001 未先应用）。
  SELECT count(*) INTO v_missing FROM sync_table_registry WHERE cardinality(cols) = 0;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'sync_table_registry 有 % 张表未从 information_schema 取到列清单'
                    '（请确认 0001_init.sql 已先应用）', v_missing;
  END IF;
END $$;

-- 注册表只被 RPC（definer）读写：RLS 启用且不建策略 → 直接 REST 访问全拒
--（authenticated 亦无策略），无泄密面。
ALTER TABLE sync_table_registry ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- ③ 服务端权威 revision 索引：pull 资格分支 revision > 投递水位 需按
--    (user_id, revision) 命中（对照 0001 的 (user_id, hlc) 索引补齐另一半）
-- -----------------------------------------------------------------------------
CREATE INDEX idx_entries_user_revision               ON entries (user_id, revision);
CREATE INDEX idx_entry_lines_user_revision           ON entry_lines (user_id, revision);
CREATE INDEX idx_food_items_user_revision            ON food_items (user_id, revision);
CREATE INDEX idx_ledgers_user_revision               ON ledgers (user_id, revision);
CREATE INDEX idx_categories_user_revision            ON categories (user_id, revision);
CREATE INDEX idx_budgets_user_revision               ON budgets (user_id, revision);
CREATE INDEX idx_todos_user_revision                 ON todos (user_id, revision);
CREATE INDEX idx_fitness_sessions_user_revision      ON fitness_sessions (user_id, revision);
CREATE INDEX idx_fitness_plans_user_revision         ON fitness_plans (user_id, revision);
CREATE INDEX idx_exercise_sets_user_revision         ON exercise_sets (user_id, revision);
CREATE INDEX idx_savings_goals_user_revision         ON savings_goals (user_id, revision);
CREATE INDEX idx_savings_contrib_user_revision       ON savings_contributions (user_id, revision);
CREATE INDEX idx_corrections_user_revision           ON corrections (user_id, revision);
CREATE INDEX idx_theme_profiles_user_revision        ON theme_profiles (user_id, revision);

-- =============================================================================
-- ④ sync_push_batch —— 写路径 RPC（§6.2 POST /rpc/sync_push）
--
-- 参数：
--   p_device_id  客户端设备标识（12 位 hex，§6.3 节点段；入参即设备级身份）
--   p_ops        [{ outbox_id, table_name, row_id, op, payload(jsonb 对象),
--                   hlc, base_revision? }, …]
-- 返回：
--   { acks:       [{ outbox_id, revision(=op_seq), acked_at(UTC ms) }],
--     rejections: [{ outbox_id, reason(wire), message }] }
-- 校验序（§6.2 清单 × §6.5 矩阵，与客户端 InMemorySyncBackend 逐条对齐）：
--   结构 → 表登记白名单 → schema_ver 超档 → 幂等重放 → hlc 严格递增 →
--   baseRevision 乐观校验（todos 并发 unset 例外：走 set 胜合并）→
--   墓碑拒绝复活 → 父行存在性 → 签发 op_seq → 同事务落行。
-- =============================================================================
CREATE OR REPLACE FUNCTION sync_push_batch(p_device_id text, p_ops jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid         uuid;
  v_acked_at    bigint;
  v_now_ms      bigint;
  i             integer;
  op            jsonb;
  v_outbox_id   text;
  v_table       text;
  v_row_id      text;
  v_op          text;
  v_payload     jsonb;
  v_hlc         text;
  v_base_rev    numeric;  -- jsonb number → numeric（防小数/巨数 ::bigint 炸整批）
  v_reg         sync_table_registry%ROWTYPE;
  v_existing    record;
  v_owner       record;
  v_dummy       integer;
  v_found       boolean := false;
  v_in_phys     bigint;
  v_in_ctr      bigint;
  v_ex_phys     bigint;
  v_ex_ctr      bigint;
  v_todo_merge  boolean := false;
  v_op_seq      bigint;
  v_replay      bigint;
  v_overlay     jsonb;
  v_final       jsonb;
  v_set_list    text;
  v_parent_id   text;
  v_acks        jsonb := '[]'::jsonb;
  v_rejections  jsonb := '[]'::jsonb;
BEGIN
  -- ── 服务端身份与设备（决策 A/H）───────────────────────────────────────
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sync_push_batch 需要已登录用户（§6.2：anon 无同步权限）'
      USING ERRCODE = '42501';
  END IF;
  v_now_ms := (extract(epoch FROM clock_timestamp()) * 1000)::bigint;
  v_acked_at := v_now_ms;

  IF p_device_id IS NULL OR p_device_id = '' THEN
    RAISE EXCEPTION 'sync_push_batch 缺少 device_id（§6.3）'
      USING ERRCODE = '22023';
  END IF;

  -- 已吊销设备不得出网（§5.6⑰ 一键下线的服务端半边）；未注册放行（H）。
  IF EXISTS (SELECT 1 FROM devices d
             WHERE d.id = p_device_id AND d.user_id = v_uid
               AND d.revoked_at IS NOT NULL) THEN
    RAISE EXCEPTION '设备 % 已被吊销（§5.6⑰ revoked_at）', p_device_id
      USING ERRCODE = '42501';
  END IF;

  IF p_ops IS NULL OR jsonb_typeof(p_ops) <> 'array' THEN
    RAISE EXCEPTION 'p_ops 必须是 jsonb 数组（§6.2 写路径批次）'
      USING ERRCODE = '22023';
  END IF;

  FOR i IN 0 .. jsonb_array_length(p_ops) - 1 LOOP
    -- 迭代级状态复位（防上一条的 record/布尔/seq 状态串扰：v_op_seq 必须归
    -- NULL——ON CONFLICT 空返回不赋值，残留旧值会令「并发重复重放」分支
    -- 失效、误以旧 op_seq 作 revision 写行）。
    op := p_ops -> i;
    v_found := false;
    v_todo_merge := false;
    v_op_seq := NULL;
    v_outbox_id := op ->> 'outbox_id';
    v_table     := op ->> 'table_name';
    v_row_id    := op ->> 'row_id';
    v_op        := op ->> 'op';
    v_payload   := op -> 'payload';
    v_hlc       := op ->> 'hlc';
    v_base_rev  := NULL;

    -- ── ① 结构校验（确定性拒绝：unknown）───────────────────────────────
    -- 数值入参必须是 jsonb number（防 ::bigint 文本转换炸整批）。
    IF v_outbox_id IS NULL OR v_table IS NULL OR v_row_id IS NULL
       OR v_op IS NULL OR v_hlc IS NULL
       OR jsonb_typeof(v_payload) <> 'object'
       OR v_op NOT IN ('upsert', 'delete')
       OR v_hlc !~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$'
       OR ((op -> 'base_revision') IS NOT NULL
           AND jsonb_typeof(op -> 'base_revision') <> 'number')
       OR ((v_payload -> 'schema_ver') IS NOT NULL
           AND jsonb_typeof(v_payload -> 'schema_ver') <> 'number')
       OR v_payload ->> 'id' IS DISTINCT FROM v_row_id
       OR v_payload ->> 'hlc' IS DISTINCT FROM v_hlc THEN
      v_rejections := v_rejections || jsonb_build_object(
        'outbox_id', coalesce(v_outbox_id, ''),
        'reason', 'unknown',
        'message', 'op 结构非法（§5.6⑯：字段缺失/op 枚举外/hlc 定宽编码违规/'
                   '数值字段类型非法/payload.id 与 row_id 不一致）');
      CONTINUE;
    END IF;
    v_base_rev := (op ->> 'base_revision')::numeric;

    -- ── ② 表登记白名单（同步协议表集 W1 冻结，§5.1）────────────────────
    SELECT * INTO v_reg FROM sync_table_registry WHERE table_name = v_table;
    IF NOT FOUND THEN
      v_rejections := v_rejections || jsonb_build_object(
        'outbox_id', v_outbox_id, 'reason', 'unknown',
        'message', format('未知同步表 %s（§5.1 冻结表集之外无同步语义）', v_table));
      CONTINUE;
    END IF;

    -- ── ③ schema_ver 协商（§6.4：超档拒绝——本协议无法理解该行）─────────
    -- jsonb 数值直接比较（防 2.5/巨数 ::integer 文本转换炸整批）；
    -- 键缺失 → NULL → 不拒绝（缺省 = 当前档 1）。
    IF (v_payload -> 'schema_ver') > to_jsonb(1) THEN
      -- 1 = 客户端 core_domain kCurrentSchemaVer（§5.1 冻结）
      v_rejections := v_rejections || jsonb_build_object(
        'outbox_id', v_outbox_id, 'reason', 'schema_ver',
        'message', format('schema_ver %s 超出服务端当前档（§6.4）',
                          v_payload ->> 'schema_ver'));
      CONTINUE;
    END IF;

    -- ── ④ 幂等重放（§6.2：幂等键 = outbox.id，重试不重复入账）──────────
    -- 拒绝不缓存：同一 outbox.id 的重试必须重新走校验（rowMissing 的父行
    -- 补上后重试应转正，§6.2「重试」语义）。
    SELECT op_seq INTO v_replay FROM sync_ops WHERE outbox_id = v_outbox_id;
    IF FOUND THEN
      v_acks := v_acks || jsonb_build_object(
        'outbox_id', v_outbox_id, 'revision', v_replay, 'acked_at', v_acked_at);
      CONTINUE;
    END IF;

    -- ── 校验区（只读；失败逐类拒绝——rejections 三分类回传，决策 D）──────
    -- 行锁读现值（SECURITY DEFINER 必须显式按 user_id 过滤，决策 A）。
    EXECUTE format('SELECT * FROM %I WHERE id = $1 AND user_id = $2 FOR UPDATE',
                   v_table)
      INTO v_existing USING v_row_id, v_uid;
    v_found := FOUND;

    IF v_found THEN
      -- ── ⑤ hlc 单调（§6.3 定宽段位比较：严格递增；stale 写拒绝，§6.5）─
      v_in_phys := split_part(v_hlc, ':', 1)::bigint;
      v_in_ctr  := split_part(v_hlc, ':', 2)::bigint;
      v_ex_phys := split_part(v_existing.hlc, ':', 1)::bigint;
      v_ex_ctr  := split_part(v_existing.hlc, ':', 2)::bigint;
      IF NOT (v_in_phys > v_ex_phys
              OR (v_in_phys = v_ex_phys AND v_in_ctr > v_ex_ctr)) THEN
        v_rejections := v_rejections || jsonb_build_object(
          'outbox_id', v_outbox_id, 'reason', 'hlc_non_monotonic',
          'message', 'hlc 单调校验失败（§6.2/§6.3：LWW 后写者胜的服务端半边）');
        CONTINUE;
      END IF;

      -- ── ⑥ todos set 胜合并判据（决策 G，§6.5 第 6 行）────────────────
      -- 「取消完成仅无并发时生效」：baseRevision 命中服务端现值（无并发）
      -- 才允许 unset；并发 unset 保留服务端 done_at（勾选永不丢失）。
      -- 嵌套 IF 保证 v_existing.done_at 仅在记录确为 todos 行时取用。
      v_todo_merge := false;
      IF v_table = 'todos' THEN
        v_todo_merge := (v_op = 'upsert'
                         AND v_existing.done_at IS NOT NULL
                         AND (v_payload ->> 'done_at') IS NULL
                         AND (v_base_rev IS NULL
                              OR v_base_rev <> v_existing.revision));
      END IF;

      -- ── ⑦ baseRevision 乐观校验（§5.6⑯；todos 并发 unset 例外已并）──
      IF NOT v_todo_merge AND v_base_rev IS NOT NULL
         AND v_base_rev <> v_existing.revision THEN
        v_rejections := v_rejections || jsonb_build_object(
          'outbox_id', v_outbox_id, 'reason', 'base_revision_conflict',
          'message', format('baseRevision 乐观校验失败（§5.6⑯：base_revision %s '
                            '≠ 服务端权威 revision %s，期间有他端写入）',
                            v_base_rev, v_existing.revision));
        CONTINUE;
      END IF;

      -- ── ⑧ 墓碑拒绝复活（§6.5 第 7 行：删后编辑保持删除胜出）─────────
      IF v_existing.deleted_at IS NOT NULL AND v_op = 'upsert'
         AND (v_payload ->> 'deleted_at') IS NULL THEN
        v_rejections := v_rejections || jsonb_build_object(
          'outbox_id', v_outbox_id, 'reason', 'tombstone_conflict',
          'message', '墓碑拒绝复活（§6.5 删除行：服务端已是墓碑而本次为存活 upsert）');
        CONTINUE;
      END IF;
    END IF;

    -- ── ⑨ 行存在性（§6.2：子表父行缺失拒绝；corrections 无父检查）────
    IF v_reg.parent_table IS NOT NULL THEN
      v_parent_id := v_payload ->> v_reg.parent_key;
      IF v_parent_id IS NOT NULL THEN
        -- 父表名来自注册表白名单（非客户端输入），format 拼接注入安全（F）；
        -- 父行属主校验（决策 A）：他端用户的同 id 父行不构成存在性。
        EXECUTE format('SELECT 1 FROM %I WHERE id = $1 AND user_id = $2',
                       v_reg.parent_table)
          INTO v_dummy USING v_parent_id, v_uid;
        IF NOT FOUND THEN
          v_rejections := v_rejections || jsonb_build_object(
            'outbox_id', v_outbox_id, 'reason', 'row_missing',
            'message', format('父行缺失：%s/%s（§6.2 行存在性）',
                              v_reg.parent_table, v_parent_id));
          CONTINUE;
        END IF;
      END IF;
    END IF;

    -- ── ⑩ 跨用户 id 占用拦截（决策 A：id 是全局 PK，SECURITY DEFINER
    --    绕过 RLS，必须显式防「他端用户同 id 行」被 ON CONFLICT 越权覆写）
    IF NOT v_found THEN
      EXECUTE format('SELECT user_id FROM %I WHERE id = $1', v_table)
        INTO v_owner USING v_row_id;
      IF FOUND AND v_owner.user_id IS DISTINCT FROM v_uid THEN
        v_rejections := v_rejections || jsonb_build_object(
          'outbox_id', v_outbox_id, 'reason', 'unknown',
          'message', 'row id 已被其他用户占用（§6.2 RLS 强化）');
        CONTINUE;
      END IF;
    END IF;

    -- ── 写区（唯一带异常护栏的子事务：sync_ops 与行写入同生共死，B）────
    BEGIN
      -- ⑪ 接受：签发权威 op_seq（幂等键唯一约束兜底并发重复，B/C）。
      INSERT INTO sync_ops (user_id, device_id, outbox_id, table_name,
                            row_id, op, base_revision)
      VALUES (v_uid, p_device_id, v_outbox_id, v_table, v_row_id, v_op,
              v_base_rev)
      ON CONFLICT (outbox_id) DO NOTHING
      RETURNING op_seq INTO v_op_seq;

      IF v_op_seq IS NULL THEN
        -- 并发重复：另一连接刚入账 → 重放其回执（本条未做任何行写入）。
        SELECT op_seq INTO v_replay FROM sync_ops WHERE outbox_id = v_outbox_id;
        v_acks := v_acks || jsonb_build_object(
          'outbox_id', v_outbox_id, 'revision', v_replay, 'acked_at', v_acked_at);
        CONTINUE;
      END IF;

      -- ⑫ 合并行快照（决策 F）：现有行基底 || payload || 权威列覆盖。
      --    现有行基底使 payload 缺键保留服务端现值（等价「只更新载荷列」）；
      --    jsonb_populate_record 忽略未知键（§6.4 老服务端忽略新列的对侧）。
      v_overlay := jsonb_build_object(
        'revision',  v_op_seq,      -- 权威 revision = op_seq（§6.2 签发）
        'user_id',   v_uid,         -- 服务端签发，不信任客户端（决策 A）
        'device_id', p_device_id);  -- 设备身份取传输层入参（§5.1 最后写入设备）
      IF v_op = 'delete' AND (v_payload ->> 'deleted_at') IS NULL THEN
        -- delete 快照未带墓碑时刻：服务端兜底签发（§5.1 软删）。
        v_overlay := v_overlay || jsonb_build_object('deleted_at', v_now_ms);
      END IF;
      IF v_todo_merge THEN
        v_overlay := v_overlay
          || jsonb_build_object('done_at', to_jsonb(v_existing.done_at));
      END IF;
      IF v_found THEN
        v_final := to_jsonb(v_existing) || v_payload || v_overlay;
      ELSE
        v_final := v_payload || v_overlay;
      END IF;

      -- ⑬ 幂等 upsert：列名全部来自注册表白名单（注入安全，F）；
      --    ON CONFLICT 覆写亦带属主护栏（并发跨用户 id 竞态的最后防线）。
      SELECT string_agg(format('%1$I = EXCLUDED.%1$I', c), ', ')
        INTO v_set_list
        FROM unnest(v_reg.cols) AS c;
      EXECUTE format(
        'INSERT INTO %1$I SELECT jsonb_populate_record(NULL::%2$I, $1) '
        'ON CONFLICT (id) DO UPDATE SET %3$s '
        'WHERE %4$I.user_id = auth.uid()',
        v_table, v_table, v_set_list, v_table)
      USING v_final;

      v_acks := v_acks || jsonb_build_object(
        'outbox_id', v_outbox_id, 'revision', v_op_seq, 'acked_at', v_acked_at);
    EXCEPTION WHEN OTHERS THEN
      -- 意外约束冲突（如最小墓碑快照缺 NOT NULL 列）：单条随子事务回滚，
      -- 归为 unknown 拒绝（§6.2 校验清单的服务端兜底出口）。
      v_rejections := v_rejections || jsonb_build_object(
        'outbox_id', v_outbox_id, 'reason', 'unknown',
        'message', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('acks', v_acks, 'rejections', v_rejections);
END;
$$;

-- ⑤ sync_pull_changes —— 读路径 RPC（§6.2 GET /rpc/sync_pull?since_hlc=…）
--
-- 参数：
--   p_device_id  客户端设备标识
--   p_cursors    { "表名": "该表已拉取到的最大 hlc", … }（§5.6⑱ per-table 游标）
--   p_limit      单次返回行数上限（默认 200，硬上限 500）
-- 返回：
--   { changes: [{ table_name, row_id, op(upsert|delete), row(jsonb 行快照),
--                hlc, revision, schema_ver }],
--     cursors: { 表名: max(入参游标, 本批最大 hlc) }（信息性；单调只进不退，
--              客户端引擎自算游标为准）,
--     has_more: 布尔 }
-- 投递资格（决策 E）：hlc > 客户端游标 OR revision > 服务端投递水位——
-- 后者是「双端一致率 100%」的补漏半边：他端在本端游标推进之后才被接受
-- 的低 hlc 行（离线迟到写入）由 op_seq 水位兜住，永不可见洞不存在。
-- 表序 = 注册表 rank 升序（父表先于子表，§6.2）；表内按 revision 升序分批，
-- 水位推进到本批最大 revision（未投递行 revision 恒 > 水位，下轮必达）。
-- =============================================================================
CREATE OR REPLACE FUNCTION sync_pull_changes(p_device_id text,
                                             p_cursors jsonb DEFAULT '{}'::jsonb,
                                             p_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid        uuid;
  v_remaining  integer;
  r            record;
  v_cursor     text;
  v_wm         bigint;
  v_batch      jsonb;
  v_total      integer;
  v_max_seq    bigint;
  v_max_hlc    text;
  j            integer;
  v_row        jsonb;
  v_changes    jsonb := '[]'::jsonb;
  v_cursors    jsonb := '{}'::jsonb;
  v_has_more   boolean := false;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sync_pull_changes 需要已登录用户（§6.2：anon 无同步权限）'
      USING ERRCODE = '42501';
  END IF;

  -- 已吊销设备不得拉取（§5.6⑰）。
  IF EXISTS (SELECT 1 FROM devices d
             WHERE d.id = p_device_id AND d.user_id = v_uid
               AND d.revoked_at IS NOT NULL) THEN
    RAISE EXCEPTION '设备 % 已被吊销（§5.6⑰ revoked_at）', p_device_id
      USING ERRCODE = '42501';
  END IF;

  v_remaining := least(greatest(coalesce(p_limit, 200), 1), 500);

  FOR r IN SELECT * FROM sync_table_registry ORDER BY rank, table_name LOOP
    IF v_remaining <= 0 THEN
      -- 预算耗尽：后续表本轮未扫——保守置 has_more（宁可多一轮空拉，
      -- 不可丢表：已扫表的游标/水位已推进，未扫表下轮照常全量资格判定）。
      v_has_more := true;
      EXIT;
    END IF;
    v_cursor := coalesce(p_cursors ->> r.table_name, '');
    SELECT last_op_seq INTO v_wm FROM sync_pull_watermarks
      WHERE user_id = v_uid AND device_id = p_device_id
        AND table_name = r.table_name;
    v_wm := coalesce(v_wm, 0);

    EXECUTE format(
      'WITH q AS ( '
      '  SELECT to_jsonb(t) - ''user_id'' AS row_json, t.hlc, t.revision '
      '  FROM %I t '
      '  WHERE t.user_id = $1 AND (t.hlc > $2 OR t.revision > $3) '
      '), d AS ( '
      '  SELECT * FROM q ORDER BY revision LIMIT $4 '
      ') '
      'SELECT coalesce(jsonb_agg(row_json ORDER BY revision), ''[]''::jsonb), '
      '       (SELECT count(*)::integer FROM q), '
      '       (SELECT max(revision) FROM d), '
      '       (SELECT max(hlc) FROM d) '
      'FROM d', r.table_name)
    INTO v_batch, v_total, v_max_seq, v_max_hlc
    USING v_uid, v_cursor, v_wm, v_remaining;

    IF v_total IS NULL OR v_total = 0 THEN
      CONTINUE;
    END IF;
    IF jsonb_array_length(v_batch) < v_total THEN
      v_has_more := true;
    END IF;

    FOR j IN 0 .. jsonb_array_length(v_batch) - 1 LOOP
      v_row := v_batch -> j;
      v_changes := v_changes || jsonb_build_object(
        'table_name', r.table_name,
        'row_id',     v_row ->> 'id',
        'op',         CASE WHEN (v_row ->> 'deleted_at') IS NULL
                           THEN 'upsert' ELSE 'delete' END,
        'row',        v_row,
        'hlc',        v_row ->> 'hlc',
        'revision',   (v_row ->> 'revision')::bigint,
        'schema_ver', coalesce((v_row ->> 'schema_ver')::integer, 1));
    END LOOP;
    v_remaining := v_remaining - jsonb_array_length(v_batch);

    -- 水位推进（GREATEST 单调：cursor 分支重投的老行不回退水位）。
    INSERT INTO sync_pull_watermarks AS w
      (user_id, device_id, table_name, last_op_seq, updated_at)
    VALUES (v_uid, p_device_id, r.table_name, v_max_seq, now())
    ON CONFLICT (user_id, device_id, table_name)
    DO UPDATE SET last_op_seq = GREATEST(w.last_op_seq, EXCLUDED.last_op_seq),
                  updated_at  = now();

    -- W7-8 集成修复：游标单调（只进不退）。revision > 水位补投的迟到行
    -- hlc 低于既有游标——若游标直接取「本批最大 hlc」会**回退**，下轮把
    -- 已投递区间（hlc ∈ (旧批 max, 既有游标]）整段重投一遍（W7-8 飞行模式
    -- 回归 ②/全链路 ⑤ 的「二次同步无增量」即卡在此）。定宽 hlc 字典序=
    -- 时间序（§6.3），text 比较的 GREATEST 即正确的时间戳 max。
    v_cursors := v_cursors || jsonb_build_object(
      r.table_name,
      GREATEST(v_cursor, v_max_hlc));
  END LOOP;

  RETURN jsonb_build_object('changes', v_changes,
                            'cursors', v_cursors,
                            'has_more', v_has_more);
END;
$$;

-- =============================================================================
-- ⑥ register_device —— 设备注册 RPC（§5.6⑰ devices、§3.7「同步一期…+设备注册」）
--
-- 参数：p_device_id（= devices.id，与 HLC 节点段同域）、p_name、p_platform、
--       p_created_at（UTC ms，可空则服务端补 now）。
-- 返回：{ device: devices 行 jsonb, server_now: UTC ms }
-- 幂等（§5.6⑰）：重复注册 = 刷新 name/platform/last_seen；
-- - revoked_at 永不复活（一键下线后重注册仍受 push/pull 拒绝约束）；
-- - 他端用户已占用的 id：显式拒绝（RLS 强化的注册面，决策 A）。
-- =============================================================================
CREATE OR REPLACE FUNCTION register_device(p_device_id text,
                                           p_name text DEFAULT NULL,
                                           p_platform text DEFAULT 'unknown',
                                           p_created_at bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid    uuid;
  v_now_ms bigint;
  v_device devices%ROWTYPE;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'register_device 需要已登录用户（§6.2：anon 无同步权限）'
      USING ERRCODE = '42501';
  END IF;
  IF p_device_id IS NULL OR p_device_id = '' THEN
    RAISE EXCEPTION 'register_device 缺少 device_id（§6.3）'
      USING ERRCODE = '22023';
  END IF;
  v_now_ms := (extract(epoch FROM clock_timestamp()) * 1000)::bigint;

  INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at)
  VALUES (p_device_id, v_uid,
          coalesce(p_name, 'Slimca Device'),
          coalesce(p_platform, 'unknown'),
          coalesce(p_created_at, v_now_ms),
          v_now_ms)
  ON CONFLICT (id) DO UPDATE
    SET name         = EXCLUDED.name,
        platform     = EXCLUDED.platform,
        last_seen_at = EXCLUDED.last_seen_at
    WHERE devices.user_id = auth.uid()   -- 他人设备不覆写；revoked_at 不动
  RETURNING * INTO v_device;

  IF v_device.id IS NULL THEN
    -- 冲突且 WHERE 护栏未放行：查清是他人占用还是本端已注册行。
    SELECT * INTO v_device FROM devices WHERE id = p_device_id;
    IF v_device.user_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION '设备 % 已被其他用户注册（§6.2 RLS 强化）', p_device_id
        USING ERRCODE = '23505';
    END IF;
    -- 本端已注册/已吊销：刷新 last_seen（revoked_at 保持不复活）。
    UPDATE devices SET last_seen_at = v_now_ms
      WHERE id = p_device_id AND user_id = v_uid;
    SELECT * INTO v_device FROM devices WHERE id = p_device_id;
  END IF;

  RETURN jsonb_build_object('device', to_jsonb(v_device),
                            'server_now', v_now_ms);
END;
$$;

-- =============================================================================
-- ⑦ 执行权限加固（RLS 强化收尾）：RPC 只对 authenticated 开放；anon/PUBLIC
--    一律撤回。注册表/水位表维持 definer-only（RLS 无策略默认全拒）。
-- =============================================================================
REVOKE ALL ON FUNCTION sync_push_batch(text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION sync_push_batch(text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION sync_push_batch(text, jsonb) TO authenticated;

REVOKE ALL ON FUNCTION sync_pull_changes(text, jsonb, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sync_pull_changes(text, jsonb, integer) FROM anon;
GRANT EXECUTE ON FUNCTION sync_pull_changes(text, jsonb, integer) TO authenticated;

REVOKE ALL ON FUNCTION register_device(text, text, text, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION register_device(text, text, text, bigint) FROM anon;
GRANT EXECUTE ON FUNCTION register_device(text, text, text, bigint) TO authenticated;

REVOKE ALL ON sync_table_registry FROM anon, authenticated;

COMMIT;

-- =============================================================================
-- 部署与联调边界（W7-8）：
-- - 本迁移与客户端 SupabaseSyncBackend（packages/feature_sync）按上文线协议
--   对接；端到端联调需要 Supabase 项目凭据（SyncConfig{url, anonKey}）——
--   用户尚未提供，真实端点验证「待用户凭据」。
-- - 墓碑 90 天物理 GC、sync_ops/sync_pull_watermarks 的历史清理（§5.1/§6.5）
--   为后续定时任务迁移，不在本文件范围。
-- - 已知边界（诚实写明）：entry_lines.ledger_id / category_id 等维度引用
--   仅受「全局存在」外键约束，不做跨用户引用校验（与 InMemory Fake 同一
--   校验面；引用行仍只随属主同步，无数据泄露路径）。
-- =============================================================================
