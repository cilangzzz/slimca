-- =============================================================================
-- Slimca 服务端初始迁移：schema v1（W1 冻结）
-- 依据 docs/design/产品设计文档.md：
--   §5.1 通用约定（主键 / 公共列 / 金额 / 日期 / 软删 / 派生量）
--   §5.2-§5.6 实体字段与索引清单（①-㉑ 编号沿用文档）
--   §6.1 原则 3「投影不同步」、原则 2「append-first」
--   §6.2 架构与读写路径（RLS 按 user_id 行级隔离 / op seq BIGSERIAL + outbox.id 幂等）
--   §6.3 HLC 定宽编码（字典序=全序）
--   §6.4 schema 演进（v1-v3 冻结期禁破坏性迁移）
--
-- 总体设计决策：
--   1. 服务端只承载会同步的数据：「同步真值表 14 张」+「服务端为主 2 张（devices /
--      attachments）」，与客户端 Drift schema 同构（§6.2「表结构同构，杜绝漂移」）。
--   2. 客户端「本地件 5 张」不建服务端表：
--        day_summary   §5.6⑬ 投影（§6.1 原则 3：聚合/统计/余额永不上服务端）
--        ai_parses     §5.6⑭ 本地缓存（entries.ai_parse_id 仅存其 id 做溯源）
--        sync_outbox   §5.6⑯ 客户端出网队列（服务端只留其 id 作幂等键，见 sync_ops）
--        sync_cursors  §5.6⑰ 客户端 per-table 拉取游标
--        settings      §5.1 本地件（注意：§6.5 冲突矩阵把 settings 列入标量 LWW，
--                      若后续把标量配置上云，以增量迁移补表，本迁移按 §5.1 冻结清单不加）
--   3. 类型映射（Drift/SQLite ↔ Postgres，保证两侧取值域一致）：
--        Drift TEXT          ↔ TEXT
--        Drift INTEGER       ↔ BIGINT   -- SQLite INTEGER 是 64 位而 PG INTEGER 只有 32 位；
--                                       -- UTC 毫秒时间戳（约 1.7e12）与 revision=服务端
--                                       -- BIGSERIAL seq 均超 32 位，故一律取 BIGINT
--        Drift REAL          ↔ DOUBLE PRECISION   -- 8 字节 IEEE 浮点一一对应
--        Drift INTEGER(bool) ↔ BOOLEAN
--        「TEXT(JSON)」      ↔ TEXT（两侧同为 TEXT 存 JSON 字符串，保持同构）
--   4. 主键 id 一律 TEXT 存 UUIDv7（§5.1：时间有序、同步友好），由客户端生成，
--      服务端不生成主键。
--   5. user_id 为服务端专用列（客户端 Drift 本地表无此列），仅供 RLS 行级隔离（§6.2）。
--   6. created_at/updated_at/hlc/revision 等同步语义列一律由客户端写入，服务端不得改写
--      （LWW 以 hlc 为序，§6.5），因此刻意不建 updated_at 触发器。
--   7. 软删墓碑 90 天物理清理（GC）由后续迁移的 RPC/定时任务实现（§5.1/§6.5），本迁移只建结构。
--   8. RLS：全部表 enable + 按 user_id 的基础策略骨架（文件末尾统一段）；
--      sync_push/sync_pull RPC（§6.2，后续迁移）以 security definer / service role
--      运行时绕过 RLS，自行承担「schema_ver / 行存在性 / hlc 单调」校验。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ① entries —— 事件主干（一件事）  §5.2①
--    客户端对应：packages/core_db Drift 表 entries（schema v1）
-- -----------------------------------------------------------------------------
CREATE TABLE entries (
  id            TEXT PRIMARY KEY,                       -- UUIDv7 TEXT 存储（§5.1）
  user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
                -- 服务端专用列：RLS 行级隔离（§6.2），Drift 侧无此列
  date          TEXT NOT NULL,                          -- 本地日历日 yyyy-MM-dd（§5.1，杜绝 UTC 错日）
  tz_offset_min BIGINT NOT NULL,                        -- 录入时本地时区偏移（分钟）
  occurred_at   BIGINT,                                 -- 事件发生时刻 UTC ms（可早于录入时刻）
  kind          TEXT NOT NULL,                          -- food/fitness/expense/mixed/note
  source        TEXT NOT NULL,                          -- text/voice/photo/receipt/chip/manual
  title         TEXT NOT NULL,                          -- 一句话描述（AI 生成或用户输入）
  note          TEXT,
  status        TEXT NOT NULL,                          -- draft（AI 字段可被新解析覆盖）/confirmed/edited
  ai_parse_id   TEXT,                                   -- → 客户端本地表 ai_parses.id（本地件不上云，无 FK，§5.2①）
  device_id     TEXT NOT NULL,                          -- 公共列「最后写入设备」；插入即创建设备（§5.1/§5.2①）
  created_at    BIGINT NOT NULL,                        -- UTC ms，客户端写入（§5.1）
  updated_at    BIGINT NOT NULL,                        -- UTC ms，同步游标（§6.2）
  deleted_at    BIGINT,                                 -- 软删墓碑，NULL=未删（§5.1）
  hlc           TEXT NOT NULL,                          -- 定宽 HLC，字典序=全序（§6.3）
  revision      BIGINT NOT NULL DEFAULT 0,              -- 0=服务端未签发；sync_push 后回写权威 seq（§5.1/§6.2）
  schema_ver    INTEGER NOT NULL DEFAULT 1,             -- 行级 schema 版本（§5.1/§6.4）
  CONSTRAINT entries_kind_chk   CHECK (kind IN ('food', 'fitness', 'expense', 'mixed', 'note')),
  CONSTRAINT entries_source_chk CHECK (source IN ('text', 'voice', 'photo', 'receipt', 'chip', 'manual')),
  CONSTRAINT entries_status_chk CHECK (status IN ('draft', 'confirmed', 'edited')),
  CONSTRAINT entries_date_chk   CHECK (date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  CONSTRAINT entries_tz_chk     CHECK (tz_offset_min BETWEEN -840 AND 840),
  CONSTRAINT entries_hlc_chk    CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

-- §5.2① 索引清单 (date)/(kind,date)/(updated_at)/(hlc)，多租户下统一加 user_id 前缀
--（RLS 查询恒带 user_id，前缀索引才能命中）
CREATE INDEX idx_entries_user_date      ON entries (user_id, date);
CREATE INDEX idx_entries_user_kind_date ON entries (user_id, kind, date);
CREATE INDEX idx_entries_user_updated   ON entries (user_id, updated_at);
CREATE INDEX idx_entries_user_hlc       ON entries (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ④ ledgers —— 账本  §5.4④（先于 entry_lines 建表以满足 FK 依赖）
--    客户端对应：packages/core_db Drift 表 ledgers
--    MVP 建表但恒默认 money 账本（schema 先冻结、功能后启用，§5.4④）
-- -----------------------------------------------------------------------------
CREATE TABLE ledgers (
  id                    TEXT PRIMARY KEY,
  user_id               uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  icon                  TEXT NOT NULL,
  currency              TEXT NOT NULL,                  -- kcal 账本币种=kcal（§5.4④）
  kind                  TEXT NOT NULL,                  -- money/kcal；kcal 账本系统内置、不可删不可多开
  sort                  BIGINT NOT NULL DEFAULT 0,
  opening_balance_minor BIGINT NOT NULL DEFAULT 0,      -- 期初余额（分或 kcal）
  is_archived           BOOLEAN NOT NULL DEFAULT FALSE, -- Drift INTEGER(bool) ↔ BOOLEAN
  created_at            BIGINT NOT NULL,
  updated_at            BIGINT NOT NULL,
  deleted_at            BIGINT,
  hlc                   TEXT NOT NULL,
  revision              BIGINT NOT NULL DEFAULT 0,
  schema_ver            INTEGER NOT NULL DEFAULT 1,
  device_id             TEXT NOT NULL,
  CONSTRAINT ledgers_kind_chk CHECK (kind IN ('money', 'kcal')),
  CONSTRAINT ledgers_hlc_chk  CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_ledgers_user_kind    ON ledgers (user_id, kind);
CREATE INDEX idx_ledgers_user_updated ON ledgers (user_id, updated_at);
CREATE INDEX idx_ledgers_user_hlc     ON ledgers (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑤ categories —— 分类  §5.4⑤
--    客户端对应：packages/core_db Drift 表 categories
-- -----------------------------------------------------------------------------
CREATE TABLE categories (
  id          TEXT PRIMARY KEY,
  user_id     uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  icon        TEXT NOT NULL,
  sort        BIGINT NOT NULL DEFAULT 0,
  ledger_id   TEXT REFERENCES ledgers (id),   -- NULL=全局分类（§5.4⑤）
  kind        TEXT NOT NULL,                  -- expense/income
  color_token TEXT NOT NULL,                  -- 引用语义 token 名而非裸色值（换肤前提，§5.4⑤/§8.2）
  is_preset   BOOLEAN NOT NULL DEFAULT FALSE, -- 内置 20+ 中文分类不可删
  created_at  BIGINT NOT NULL,
  updated_at  BIGINT NOT NULL,
  deleted_at  BIGINT,
  hlc         TEXT NOT NULL,
  revision    BIGINT NOT NULL DEFAULT 0,
  schema_ver  INTEGER NOT NULL DEFAULT 1,
  device_id   TEXT NOT NULL,
  CONSTRAINT categories_kind_chk CHECK (kind IN ('expense', 'income')),
  CONSTRAINT categories_hlc_chk  CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_categories_user_ledger   ON categories (user_id, ledger_id);
CREATE INDEX idx_categories_user_kind     ON categories (user_id, kind);
CREATE INDEX idx_categories_user_updated  ON categories (user_id, updated_at);
CREATE INDEX idx_categories_user_hlc      ON categories (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ② entry_lines —— 产出行（facet 行，差异化的物理落点）  §5.2②
--    客户端对应：packages/core_db Drift 表 entry_lines
--    设计要点：金额/热量/消耗拆成行而非列（§5.3），多端并发改不同维度互不覆盖，
--    多数冲突在数据结构层被消灭；同 facet 行同字段并发才交给行级 LWW（§6.5）
-- -----------------------------------------------------------------------------
CREATE TABLE entry_lines (
  id            TEXT PRIMARY KEY,
  user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  entry_id      TEXT NOT NULL REFERENCES entries (id),
                -- FK 不设级联物理删：软删不级联（§5.2②），物理清理由 GC 任务统一处理
  type          TEXT NOT NULL,                  -- calorie（摄入）/burn（运动消耗）/money（金额）
  amount        BIGINT NOT NULL,                -- calorie/burn=kcal；money=分（正数，0 允许）
                -- 正负语义由 direction 承载，amount 恒非负（§5.2②）
  direction     TEXT NOT NULL,                  -- in/out（calorie=in；burn=out；money 按 expense=out/income=in）
  ledger_id     TEXT REFERENCES ledgers (id),   -- money 行必填（见 CHECK）；kcal 行归集内置 kcal 账本
  category_id   TEXT REFERENCES categories (id),-- money 行=消费分类；calorie 行可挂餐饮子类
  currency      TEXT DEFAULT 'CNY',             -- money 行，默认 CNY（§5.2②）
  confidence    DOUBLE PRECISION,               -- AI 置信度 0-1（AI 产出行必填，由 RPC 层校验）
  payload       TEXT,                           -- JSON：商户/支付方式/MET 参数/菜品数组摘要（§5.2②）
  correction_of TEXT REFERENCES entry_lines (id),-- 修正=新增行，旧行 status→superseded（§5.2②/§6.5）
  status        TEXT NOT NULL DEFAULT 'active', -- active/superseded（被修正）/void（作废）
  created_at    BIGINT NOT NULL,
  updated_at    BIGINT NOT NULL,
  deleted_at    BIGINT,
  hlc           TEXT NOT NULL,
  revision      BIGINT NOT NULL DEFAULT 0,
  schema_ver    INTEGER NOT NULL DEFAULT 1,
  device_id     TEXT NOT NULL,
  CONSTRAINT entry_lines_type_chk           CHECK (type IN ('calorie', 'burn', 'money')),
  CONSTRAINT entry_lines_direction_chk      CHECK (direction IN ('in', 'out')),
  CONSTRAINT entry_lines_status_chk         CHECK (status IN ('active', 'superseded', 'void')),
  CONSTRAINT entry_lines_amount_chk         CHECK (amount >= 0),
  CONSTRAINT entry_lines_confidence_chk     CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  CONSTRAINT entry_lines_money_ledger_chk   CHECK (type <> 'money' OR ledger_id IS NOT NULL),
  CONSTRAINT entry_lines_money_currency_chk CHECK (type <> 'money' OR currency IS NOT NULL),
  CONSTRAINT entry_lines_hlc_chk            CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

-- §5.2② 索引清单 (entry_id)/(type)/(ledger_id,updated_at)/(correction_of)/(hlc)
CREATE INDEX idx_entry_lines_user_entry         ON entry_lines (user_id, entry_id);
CREATE INDEX idx_entry_lines_user_type          ON entry_lines (user_id, type);
CREATE INDEX idx_entry_lines_user_ledger_update ON entry_lines (user_id, ledger_id, updated_at);
CREATE INDEX idx_entry_lines_user_correction    ON entry_lines (user_id, correction_of);
CREATE INDEX idx_entry_lines_user_updated       ON entry_lines (user_id, updated_at);
CREATE INDEX idx_entry_lines_user_hlc           ON entry_lines (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ③ food_items —— 菜品明细（calorie 行子表）  §5.2③
--    客户端对应：packages/core_db Drift 表 food_items
-- -----------------------------------------------------------------------------
CREATE TABLE food_items (
  id            TEXT PRIMARY KEY,
  user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  entry_id      TEXT NOT NULL REFERENCES entries (id),
  line_id       TEXT NOT NULL REFERENCES entry_lines (id),  -- 挂在 calorie 行下（§5.2③/§5.7）
  name          TEXT NOT NULL,                              -- 菜品名（中文优先）
  portion_g     DOUBLE PRECISION NOT NULL,                  -- 份量（克），滑杆联动重算基准
  kcal          BIGINT NOT NULL,
  protein_g     DOUBLE PRECISION,                           -- 未知宏量取 NULL（避免 0 污染校准均值）
  carb_g        DOUBLE PRECISION,
  fat_g         DOUBLE PRECISION,
  ref_source    TEXT NOT NULL,                              -- usda/off/baidu/local/llm（联查来源）
  ref_id        TEXT,                                       -- 来源库条目 id
  confidence    DOUBLE PRECISION,   -- 判断标注：文档未标「?」，但人工录入（chip/manual）无 AI 置信度，
                                    -- 语义与 §5.2② confidence（AI 产出行必填）一致，取可空；若 Drift 侧
                                    -- 定义为 NOT NULL 需两侧对齐
  user_adjusted BOOLEAN NOT NULL DEFAULT FALSE,             -- 用户是否改过（校准信号）
  created_at    BIGINT NOT NULL,
  updated_at    BIGINT NOT NULL,
  deleted_at    BIGINT,
  hlc           TEXT NOT NULL,
  revision      BIGINT NOT NULL DEFAULT 0,
  schema_ver    INTEGER NOT NULL DEFAULT 1,
  device_id     TEXT NOT NULL,
  CONSTRAINT food_items_ref_source_chk  CHECK (ref_source IN ('usda', 'off', 'baidu', 'local', 'llm')),
  CONSTRAINT food_items_confidence_chk  CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  CONSTRAINT food_items_hlc_chk         CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_food_items_user_entry   ON food_items (user_id, entry_id);
CREATE INDEX idx_food_items_user_line    ON food_items (user_id, line_id);
CREATE INDEX idx_food_items_user_updated ON food_items (user_id, updated_at);
CREATE INDEX idx_food_items_user_hlc     ON food_items (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑥ budgets —— 预算  §5.4⑥
--    客户端对应：packages/core_db Drift 表 budgets
-- -----------------------------------------------------------------------------
CREATE TABLE budgets (
  id                 TEXT PRIMARY KEY,
  user_id            uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  ledger_id          TEXT NOT NULL REFERENCES ledgers (id),  -- 预算归属账本（含 kcal 账本）
  category_id        TEXT REFERENCES categories (id),        -- NULL=总预算
  period_type        TEXT NOT NULL,                          -- daily（P0）/monthly（P1）
  amount             BIGINT NOT NULL,                        -- money=分；kcal 账本=kcal
  day_of_month_start BIGINT,                                 -- 月度周期起点（P1）
  carry_over         BOOLEAN NOT NULL DEFAULT FALSE,         -- 结转开关（P1）
  created_at         BIGINT NOT NULL,
  updated_at         BIGINT NOT NULL,
  deleted_at         BIGINT,
  hlc                TEXT NOT NULL,
  revision           BIGINT NOT NULL DEFAULT 0,
  schema_ver         INTEGER NOT NULL DEFAULT 1,
  device_id          TEXT NOT NULL,
  CONSTRAINT budgets_period_chk CHECK (period_type IN ('daily', 'monthly')),
  CONSTRAINT budgets_hlc_chk    CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_budgets_user_ledger   ON budgets (user_id, ledger_id);
CREATE INDEX idx_budgets_user_period   ON budgets (user_id, period_type);
CREATE INDEX idx_budgets_user_updated  ON budgets (user_id, updated_at);
CREATE INDEX idx_budgets_user_hlc      ON budgets (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑦ fitness_sessions —— 健身会话  §5.5⑦
--    客户端对应：packages/core_db Drift 表 fitness_sessions
--    会话落库时同事务产出 entry(kind=fitness) + entry_lines(type=burn)，
--    burn 行 payload 记 session_id——消耗行与钱/热量行共用同一 facet 行同步模型（§2.2/§5.5⑦）
-- -----------------------------------------------------------------------------
CREATE TABLE fitness_sessions (
  id            TEXT PRIMARY KEY,
  user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  date          TEXT NOT NULL,
  tz_offset_min BIGINT NOT NULL,
  start_at      BIGINT,             -- 开始时刻 UTC ms
  duration_s    BIGINT NOT NULL,    -- 时长（秒）
  type          TEXT NOT NULL,      -- strength/cardio/hiit/other/template_instance
  kcal_burn     BIGINT NOT NULL,    -- MET 表估算，UI 按 ±20% 口径标注（§5.5⑦）
  entry_id      TEXT REFERENCES entries (id),  -- → entries(kind=fitness)
  source        TEXT NOT NULL,      -- manual/timer/plan
  plan_day_id   TEXT,               -- → 健身计划排期日（P1）；排期日是模板派生量、无独立表，故不设 FK
  note          TEXT,
  created_at    BIGINT NOT NULL,
  updated_at    BIGINT NOT NULL,
  deleted_at    BIGINT,
  hlc           TEXT NOT NULL,
  revision      BIGINT NOT NULL DEFAULT 0,
  schema_ver    INTEGER NOT NULL DEFAULT 1,
  device_id     TEXT NOT NULL,
  CONSTRAINT fitness_sessions_type_chk   CHECK (type IN ('strength', 'cardio', 'hiit', 'other', 'template_instance')),
  CONSTRAINT fitness_sessions_source_chk CHECK (source IN ('manual', 'timer', 'plan')),
  CONSTRAINT fitness_sessions_date_chk   CHECK (date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  CONSTRAINT fitness_sessions_tz_chk     CHECK (tz_offset_min BETWEEN -840 AND 840),
  CONSTRAINT fitness_sessions_hlc_chk    CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_fitness_sessions_user_date   ON fitness_sessions (user_id, date);
CREATE INDEX idx_fitness_sessions_user_entry  ON fitness_sessions (user_id, entry_id);
CREATE INDEX idx_fitness_sessions_user_update ON fitness_sessions (user_id, updated_at);
CREATE INDEX idx_fitness_sessions_user_hlc    ON fitness_sessions (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑧ fitness_plans —— 健身计划（P1）  §5.5⑧
--    客户端对应：packages/core_db Drift 表 fitness_plans
-- -----------------------------------------------------------------------------
CREATE TABLE fitness_plans (
  id           TEXT PRIMARY KEY,
  user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  weekday_mask BIGINT NOT NULL DEFAULT 0,  -- bit0=周一…bit6=周日 排期掩码（§5.5⑧）
  exercises    TEXT NOT NULL,              -- JSON 排期模板：动作/组数/重量配比/休息秒
  start_date   TEXT NOT NULL,
  active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   BIGINT NOT NULL,
  updated_at   BIGINT NOT NULL,
  deleted_at   BIGINT,
  hlc          TEXT NOT NULL,
  revision     BIGINT NOT NULL DEFAULT 0,
  schema_ver   INTEGER NOT NULL DEFAULT 1,
  device_id    TEXT NOT NULL,
  CONSTRAINT fitness_plans_date_chk CHECK (start_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  CONSTRAINT fitness_plans_hlc_chk  CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_fitness_plans_user_active  ON fitness_plans (user_id, active);
CREATE INDEX idx_fitness_plans_user_updated ON fitness_plans (user_id, updated_at);
CREATE INDEX idx_fitness_plans_user_hlc     ON fitness_plans (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑨ exercise_sets —— 组明细（P1 功能启用；同步真值表，W1 随 schema 建表、P1 启用——
--    与 ledgers 同策略，§5.5⑨）
--    客户端对应：packages/core_db Drift 表 exercise_sets
-- -----------------------------------------------------------------------------
CREATE TABLE exercise_sets (
  id            TEXT PRIMARY KEY,
  user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  session_id    TEXT NOT NULL REFERENCES fitness_sessions (id),
  exercise_ref  TEXT NOT NULL,          -- 动作库 id 或名称
  weight_kg_x10 BIGINT NOT NULL DEFAULT 0,  -- 重量 ×10 定点（避免浮点同步问题）；自重动作=0（判断标注：
                                            -- 文档未标「?」亦未写自重语义，取 NOT NULL+0 兜底）
  reps          BIGINT NOT NULL,
  rpe           DOUBLE PRECISION,       -- REAL?（§5.5⑨）
  rest_s        BIGINT,                 -- INTEGER?（§5.5⑨）
  done_at       BIGINT NOT NULL,        -- 完成时刻 UTC ms
  sort          BIGINT NOT NULL,        -- 组序
  created_at    BIGINT NOT NULL,
  updated_at    BIGINT NOT NULL,
  deleted_at    BIGINT,
  hlc           TEXT NOT NULL,
  revision      BIGINT NOT NULL DEFAULT 0,
  schema_ver    INTEGER NOT NULL DEFAULT 1,
  device_id     TEXT NOT NULL,
  CONSTRAINT exercise_sets_hlc_chk CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_exercise_sets_user_session ON exercise_sets (user_id, session_id);
CREATE INDEX idx_exercise_sets_user_updated ON exercise_sets (user_id, updated_at);
CREATE INDEX idx_exercise_sets_user_hlc     ON exercise_sets (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑩ todos —— 待办（计划族，独立于事件模型）  §5.5⑩
--    客户端对应：packages/core_db Drift 表 todos
--    done_at 合并规则「只前进不回退：并发 set vs unset → set 胜（勾选永不丢失）」
--    属同步协议语义，由后续 sync_push RPC 实现（§6.5），schema 层不设触发器
-- -----------------------------------------------------------------------------
CREATE TABLE todos (
  id          TEXT PRIMARY KEY,
  user_id     uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  note        TEXT,
  date        TEXT,             -- 计划日；NULL=无日期收集箱（§5.5⑩）
  done_at     BIGINT,           -- 完成时刻 UTC ms；见上合并规则
  due_at      BIGINT,           -- 截止时刻 UTC ms
  repeat_rule TEXT,             -- RRULE（RFC5545，P1）
  remind_at   BIGINT,           -- 提醒（P1）
  goal_link   TEXT,             -- → savings_goals / fitness_plans（多态联动，故不设 FK，§5.5⑩）
  created_at  BIGINT NOT NULL,
  updated_at  BIGINT NOT NULL,
  deleted_at  BIGINT,
  hlc         TEXT NOT NULL,
  revision    BIGINT NOT NULL DEFAULT 0,
  schema_ver  INTEGER NOT NULL DEFAULT 1,
  device_id   TEXT NOT NULL,
  CONSTRAINT todos_date_chk CHECK (date IS NULL OR date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  CONSTRAINT todos_hlc_chk  CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_todos_user_date   ON todos (user_id, date);
CREATE INDEX idx_todos_user_done   ON todos (user_id, done_at);
CREATE INDEX idx_todos_user_update ON todos (user_id, updated_at);
CREATE INDEX idx_todos_user_hlc    ON todos (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑪ savings_goals —— 存钱目标（P1）  §5.5⑪
--    客户端对应：packages/core_db Drift 表 savings_goals
-- -----------------------------------------------------------------------------
CREATE TABLE savings_goals (
  id           TEXT PRIMARY KEY,
  user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  target_minor BIGINT NOT NULL,               -- 目标金额（分）
  deadline     TEXT,                          -- 截止日（§5.5⑪ TEXT?）
  method       TEXT NOT NULL,                 -- daily365/week52/custom
  rhythm       TEXT NOT NULL,                 -- JSON：阶梯表或每日额
  status       TEXT NOT NULL DEFAULT 'active',-- active/completed/abandoned
  started_on   TEXT NOT NULL,                 -- 起始日
  created_at   BIGINT NOT NULL,
  updated_at   BIGINT NOT NULL,
  deleted_at   BIGINT,
  hlc          TEXT NOT NULL,
  revision     BIGINT NOT NULL DEFAULT 0,
  schema_ver   INTEGER NOT NULL DEFAULT 1,
  device_id    TEXT NOT NULL,
  CONSTRAINT savings_goals_method_chk CHECK (method IN ('daily365', 'week52', 'custom')),
  CONSTRAINT savings_goals_status_chk CHECK (status IN ('active', 'completed', 'abandoned')),
  CONSTRAINT savings_goals_deadline_chk CHECK (deadline IS NULL OR deadline ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  CONSTRAINT savings_goals_started_chk  CHECK (started_on ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  CONSTRAINT savings_goals_hlc_chk      CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_savings_goals_user_status  ON savings_goals (user_id, status);
CREATE INDEX idx_savings_goals_user_updated ON savings_goals (user_id, updated_at);
CREATE INDEX idx_savings_goals_user_hlc     ON savings_goals (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑫ savings_contributions —— 存钱贡献（P1，append-only 只增不改）  §5.5⑫
--    客户端对应：packages/core_db Drift 表 savings_contributions
--    append-only（§6.1 原则 2 / §6.5 并集零冲突）：业务上只增不改，目标进度=Σ贡献行
--    由本地投影重建（§5.5⑫/§6.1 原则 3）；唯一允许的 UPDATE 是软删墓碑 deleted_at
--    （§5.1 公共列），由 RPC 层约束，不设触发器
-- -----------------------------------------------------------------------------
CREATE TABLE savings_contributions (
  id           TEXT PRIMARY KEY,
  user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  goal_id      TEXT NOT NULL REFERENCES savings_goals (id),
  date         TEXT NOT NULL,        -- 打卡日
  amount_minor BIGINT NOT NULL,      -- 金额（分）
  slot         BIGINT,               -- 365/52 周存钱法格子号
  note         TEXT,
  created_at   BIGINT NOT NULL,
  updated_at   BIGINT NOT NULL,
  deleted_at   BIGINT,
  hlc          TEXT NOT NULL,
  revision     BIGINT NOT NULL DEFAULT 0,
  schema_ver   INTEGER NOT NULL DEFAULT 1,
  device_id    TEXT NOT NULL,
  CONSTRAINT savings_contributions_date_chk CHECK (date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  CONSTRAINT savings_contributions_hlc_chk  CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_savings_contrib_user_goal     ON savings_contributions (user_id, goal_id);
CREATE INDEX idx_savings_contrib_user_date     ON savings_contributions (user_id, date);
CREATE INDEX idx_savings_contrib_user_updated  ON savings_contributions (user_id, updated_at);
CREATE INDEX idx_savings_contrib_user_hlc      ON savings_contributions (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑮ corrections —— 修正审计日志（append-only，同步真值）  §5.6⑮
--    客户端对应：packages/core_db Drift 表 corrections
--    「确认后金额不可变、修正=新增行」的数据底座：既是审计（账目可信）也是
--    个人校准资产（P2 喂个性化系数反哺提示词与默认份量，§5.6⑮）
-- -----------------------------------------------------------------------------
CREATE TABLE corrections (
  id        TEXT PRIMARY KEY,
  user_id   uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  entry_id  TEXT NOT NULL REFERENCES entries (id),
  line_id   TEXT REFERENCES entry_lines (id),
  field     TEXT NOT NULL,        -- kcal/amount/category/portion/…（开放枚举，文档含「…」，不设 CHECK）
  old_value TEXT,                 -- 判断标注：文档未标「?」；存在旧值为空（首次赋值，如给 calorie 行
                                  -- 补挂分类）的合法场景，取可空；若 Drift 侧定义为 NOT NULL 需两侧对齐
  new_value TEXT NOT NULL,
  source    TEXT NOT NULL,        -- user/ai_recalib
  created_at BIGINT NOT NULL,     -- §5.6⑮ 所列 created_at 即 §5.1 公共列（append-only，updated_at=created_at）
  updated_at BIGINT NOT NULL,
  deleted_at BIGINT,
  hlc        TEXT NOT NULL,
  revision   BIGINT NOT NULL DEFAULT 0,
  schema_ver INTEGER NOT NULL DEFAULT 1,
  device_id  TEXT NOT NULL,
  CONSTRAINT corrections_source_chk CHECK (source IN ('user', 'ai_recalib')),
  CONSTRAINT corrections_hlc_chk    CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_corrections_user_entry   ON corrections (user_id, entry_id);
CREATE INDEX idx_corrections_user_line    ON corrections (user_id, line_id);
CREATE INDEX idx_corrections_user_created ON corrections (user_id, created_at);
CREATE INDEX idx_corrections_user_updated ON corrections (user_id, updated_at);
CREATE INDEX idx_corrections_user_hlc     ON corrections (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑳ theme_profiles —— 主题包（一等同步实体，换设备主题跟随）  §5.6⑳
--    客户端对应：packages/core_db Drift 表 theme_profiles
--    tokens 引用语义 token 集（§8.2 三层架构）；motion_level 取 §9.2 MotionLevel 三档
-- -----------------------------------------------------------------------------
CREATE TABLE theme_profiles (
  id           TEXT PRIMARY KEY,
  user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  tokens       TEXT NOT NULL,                 -- JSON 语义 token 集（§8.2）
  motion_level TEXT NOT NULL DEFAULT 'full',  -- off/reduced/full（§9.2 MotionLevel；默认值为本迁移
                                              -- 判断标注，文档未指定）
  font_id      TEXT,                          -- ?（§5.6⑳）
  is_preset    BOOLEAN NOT NULL DEFAULT FALSE,
  sort         BIGINT NOT NULL DEFAULT 0,
  created_at   BIGINT NOT NULL,
  updated_at   BIGINT NOT NULL,
  deleted_at   BIGINT,
  hlc          TEXT NOT NULL,
  revision     BIGINT NOT NULL DEFAULT 0,
  schema_ver   INTEGER NOT NULL DEFAULT 1,
  device_id    TEXT NOT NULL,
  CONSTRAINT theme_profiles_motion_chk CHECK (motion_level IN ('off', 'reduced', 'full')),
  CONSTRAINT theme_profiles_hlc_chk    CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_theme_profiles_user_sort    ON theme_profiles (user_id, sort);
CREATE INDEX idx_theme_profiles_user_updated ON theme_profiles (user_id, updated_at);
CREATE INDEX idx_theme_profiles_user_hlc     ON theme_profiles (user_id, hlc);

-- -----------------------------------------------------------------------------
-- ⑰ devices —— 设备注册（服务端为主 2 张之一）  §5.6⑰
--    客户端对应：packages/core_db Drift 表 devices（注册经 RPC 完成，非行同步）
--    服务端为主表：行由设备注册 RPC 写入，不走 sync_push，故无 hlc/revision 等公共列；
--    时间列仍用 BIGINT 毫秒保持同构（§5.1）
-- -----------------------------------------------------------------------------
CREATE TABLE devices (
  id           TEXT PRIMARY KEY,        -- = device_id（UUIDv7 TEXT）；HLC 段取其前 12 hex（§6.3）
  user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL,           -- 判断标注：W1 实机为 android/ios，golden 测试跑 Linux CI（§10.1），
                                        -- 可能注册测试设备，故不设 CHECK 枚举
  created_at   BIGINT NOT NULL,         -- 注册时刻 UTC ms
  last_seen_at BIGINT,                  -- 最近心跳 UTC ms
  revoked_at   BIGINT                   -- 一键下线（P1/P2，§5.6⑰）
);

CREATE INDEX idx_devices_user ON devices (user_id);

-- -----------------------------------------------------------------------------
-- ㉑ attachments —— 附件引用登记（服务端为主 2 张之一，P1）  §5.6㉑
--    客户端对应：packages/core_db Drift 表 attachments
--    默认「解析后即焚」：原图不落服务端（local_path 仅客户端语义，服务端恒 NULL），
--    仅结构化引用可同步；blob_ref 为 P2 E2E 加密 blob 引用（§6.6）
--    attachments 是同步真值行（引用登记随同步走），故带 §5.1 公共列
-- -----------------------------------------------------------------------------
CREATE TABLE attachments (
  id           TEXT PRIMARY KEY,
  user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  entry_id     TEXT REFERENCES entries (id),  -- ?（§5.6㉑）
  content_hash TEXT NOT NULL,                 -- 去重键；同用户内查重用（不做全局 UNIQUE：
               -- 同一照片可合法挂在多条 entry 下，去重对象是 blob 而非引用行）
  kind         TEXT NOT NULL,                 -- photo/receipt
  mime         TEXT NOT NULL,
  size_bytes   BIGINT NOT NULL,
  local_path   TEXT,                          -- 客户端本地路径，服务端恒 NULL（§5.6㉑）
  blob_ref     TEXT,                          -- P2 E2E：加密 blob 引用（§6.6）
  created_at   BIGINT NOT NULL,
  updated_at   BIGINT NOT NULL,
  deleted_at   BIGINT,
  hlc          TEXT NOT NULL,
  revision     BIGINT NOT NULL DEFAULT 0,
  schema_ver   INTEGER NOT NULL DEFAULT 1,
  device_id    TEXT NOT NULL,
  CONSTRAINT attachments_kind_chk CHECK (kind IN ('photo', 'receipt')),
  CONSTRAINT attachments_hlc_chk  CHECK (hlc ~ '^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$')
);

CREATE INDEX idx_attachments_user_entry       ON attachments (user_id, entry_id);
CREATE INDEX idx_attachments_user_hash        ON attachments (user_id, content_hash);
CREATE INDEX idx_attachments_user_updated     ON attachments (user_id, updated_at);
CREATE INDEX idx_attachments_user_hlc         ON attachments (user_id, hlc);

-- -----------------------------------------------------------------------------
-- sync_ops —— 同步操作流水（§6.2 基础设施；非 §5 清单表，为协议幂等而设）
--    §6.2：「服务端校验（schema_ver / 行存在性 / hlc 单调）→ 签发权威 seq」
--          「op seq（BIGSERIAL）+ outbox.id 唯一键保证幂等（重试不重复入账）」
--    客户端对应：无 Drift 表——客户端只持 sync_outbox（§5.6⑯），
--    其 outbox.id 即本表幂等键；客户端回写 revision = op_seq（§5.1）
-- -----------------------------------------------------------------------------
CREATE TABLE sync_ops (
  op_seq        BIGSERIAL PRIMARY KEY,  -- 权威 seq（BIGSERIAL，§6.2 原文口径）
  user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
  device_id     TEXT NOT NULL,
  outbox_id     TEXT NOT NULL,          -- 幂等键 = 客户端 sync_outbox.id（§5.6⑯）
  table_name    TEXT NOT NULL,
  row_id        TEXT NOT NULL,
  op            TEXT NOT NULL,          -- upsert/delete（§5.6⑯）
  base_revision BIGINT,                 -- 乐观校验用（§5.6⑯）
  applied_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT sync_ops_outbox_id_key UNIQUE (outbox_id),  -- 重试不重复入账（§6.2）
  CONSTRAINT sync_ops_op_chk CHECK (op IN ('upsert', 'delete'))
);

CREATE INDEX idx_sync_ops_user_seq ON sync_ops (user_id, op_seq);
CREATE INDEX idx_sync_ops_user_row ON sync_ops (user_id, table_name, row_id);

-- =============================================================================
-- RLS 行级隔离策略骨架（§6.2「RLS 按 user_id 行级隔离」）
-- - 全部表 ENABLE ROW LEVEL SECURITY；anon 未登录角色无策略=默认全拒
-- - 基础策略：authenticated 用户只能读写 user_id=auth.uid() 的行
-- - auth.uid() 用 (SELECT ...) 包裹：Supabase RLS 性能建议，避免逐行重求值
-- - 后续 sync_push/sync_pull RPC（§6.2）以 security definer / service role 运行，
--   绕过 RLS 并自行做服务端校验；跨行引用（如 entry_lines.ledger_id 指向他人账本）
--   由 RPC 的「行存在性」校验拦截
-- =============================================================================
ALTER TABLE entries                ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledgers                ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories             ENABLE ROW LEVEL SECURITY;
ALTER TABLE entry_lines            ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_items             ENABLE ROW LEVEL SECURITY;
ALTER TABLE budgets                ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_sessions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_plans          ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercise_sets          ENABLE ROW LEVEL SECURITY;
ALTER TABLE todos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE savings_goals          ENABLE ROW LEVEL SECURITY;
ALTER TABLE savings_contributions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE corrections            ENABLE ROW LEVEL SECURITY;
ALTER TABLE theme_profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices                ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_ops               ENABLE ROW LEVEL SECURITY;

CREATE POLICY entries_owner_all ON entries
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY ledgers_owner_all ON ledgers
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY categories_owner_all ON categories
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY entry_lines_owner_all ON entry_lines
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY food_items_owner_all ON food_items
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY budgets_owner_all ON budgets
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY fitness_sessions_owner_all ON fitness_sessions
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY fitness_plans_owner_all ON fitness_plans
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY exercise_sets_owner_all ON exercise_sets
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY todos_owner_all ON todos
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY savings_goals_owner_all ON savings_goals
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY savings_contributions_owner_all ON savings_contributions
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY corrections_owner_all ON corrections
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY theme_profiles_owner_all ON theme_profiles
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY devices_owner_all ON devices
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY attachments_owner_all ON attachments
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY sync_ops_owner_all ON sync_ops
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
