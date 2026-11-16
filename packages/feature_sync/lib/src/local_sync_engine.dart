/// LocalSyncEngine — 本地同步引擎（§6.2 架构与读写路径的客户端实现）。
///
/// 三方法契约（core_domain `SyncEngine`，评审胜出点「可换 PowerSync/CRDT
/// 而不动 schema」）之上的本地编排：
///
/// **push（§6.2 写路径后半）**：出队批次 → [SyncBackend.push]（幂等键 =
/// outbox.id）→ ack 回写 revision/acked_at → 拒绝按 §6.2 校验项分类回处理
/// （作废/暂缓/幂等完成，见 [_handleRejection]）。
///
/// **pull（§6.2 读路径）**：per-table 游标（§5.6⑱）增量拉取 → 按「父表→
/// 子表」依赖序落库（§6.2）→ 远端行走与本地写同一校验（entries/entry_lines
/// 经 core_db 仓库：墓碑拒绝复活、金额行不可变；其余表整行 upsert + 未知列
/// 过滤=「老客户端忽略新列」，§6.4）→ 游标整批落库成功才推进 → day_summary
/// 由 dirty 自愈重算（§6.5 末行：投影不同步）。
///
/// **resolve（§6.5 冲突矩阵）**：按 [ConflictClass] 分发——LWW（HLC 定宽
/// 字典序=全序，§6.3）、append-only 并集、todo.done set 胜只前进、
/// 墓碑拒绝复活。facet 拆行的结构性免冲突发生在拆行层（§5.3），不经此仲裁。
///
/// 本地优先（§6.1 原则 1）：[syncOnce] 捕获分区/断网异常只降级状态回调，
/// 永不向上抛、永不阻塞 UI；outbox 无上限、重试幂等。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:core_domain/core_domain.dart';

import 'drift_sync_local_store.dart';
import 'sync_backend.dart';
import 'sync_table_catalog.dart';

/// 同步阶段（顶栏小圆点状态源，§6.1 原则 1「同步失败仅顶栏小圆点提示」）。
enum SyncPhase { idle, pushing, pulling, done, error }

/// 引擎状态快照。
class SyncStatus {
  final SyncPhase phase;

  /// 未确认出网条数（小圆点数字）。
  final int pending;

  /// 分区/断网等错误消息；null=正常。
  final String? error;

  final int at;

  const SyncStatus({
    required this.phase,
    required this.pending,
    this.error,
    required this.at,
  });
}

typedef SyncStatusListener = void Function(SyncStatus status);

/// 一次 [LocalSyncEngine.syncOnce] 的量化产出（§11.1 W5-6 验收口径）。
class SyncCycleReport {
  /// 送入 push 的出网条数。
  final int pushed;

  /// push ack 条数。
  final int acked;

  /// push 被拒条数（按原因分类计数）。
  final Map<SyncRejectionReason, int> rejections;

  /// 拒绝分类回处理中作废（drop）的出网条数。
  final int droppedOutbox;

  /// pull 交付的远端行数。
  final int pulled;

  /// 落库应用行数（含仲裁胜者与合并行）。
  final int applied;

  /// 仲裁跳过行数（LWW 败者、append-only 并集已存在、墓碑保护、schema_ver
  /// 超档、坏载荷）。
  final int skipped;

  /// 暂缓行数（父行未到等暂态——游标不推进，下轮重拉）。
  final int deferred;

  /// 本轮推进后的 per-table 游标（§5.6⑱）。
  final Map<String, String> cursors;

  /// 标脏的日期（day_summary 自愈重算范围，§5.6⑬）。
  final Set<String> dirtyDates;

  /// 分区/断网等错误（§6.1：只记录不抛出）。
  final Object? error;

  const SyncCycleReport({
    required this.pushed,
    required this.acked,
    required this.rejections,
    required this.droppedOutbox,
    required this.pulled,
    required this.applied,
    required this.skipped,
    required this.deferred,
    required this.cursors,
    required this.dirtyDates,
    this.error,
  });
}

/// §6.5 矩阵的本地实现引擎。
class LocalSyncEngine implements SyncEngine {
  LocalSyncEngine({
    required this.backend,
    required this.outbox,
    required this.store,
    required this.deviceId,
    HlcClock? clock,
    this.maxOutboxBatchSize = 100,
    this.maxPullRounds = 50,
    this.listener,
  }) : clock = clock ?? HlcClock(deviceId: deviceId);

  /// 远端对端（§6.2；生产为 Supabase RPC，测试为 InMemory/Loopback Fake）。
  final SyncBackend backend;

  /// 出网队列存取（§5.6⑯）。
  final SyncOutboxStore outbox;

  /// 本地真值表读写（pull 落库/游标/revision 回写，§6.2）。
  final DriftSyncLocalStore store;

  /// 本设备标识（12 位定长 hex，§6.3 节点段）。
  final String deviceId;

  /// HLC 时钟：pull 收到的远端时间戳经 [HlcClock.recv] 合并（§6.3「收到比
  /// 本地新的时间戳 → 跳变跟上」）。引擎只 recv 不 now——发戳方（UI 写路径）
  /// 与同步层必须共享同一实例（装配点保证，W7-8 bootstrap）。
  final HlcClock clock;

  /// 单批出网上限（§6.2 后台出队分批）。
  final int maxOutboxBatchSize;

  /// 单轮 syncOnce 的 pull 续拉上限（防异常死循环；正常分批远小于此）。
  final int maxPullRounds;

  /// 状态回调（顶栏小圆点）。
  final SyncStatusListener? listener;

  // ── 写路径：批量上送（§6.2 POST /rpc/sync_push 半边）──────────────────

  @override
  Future<SyncPushResult> push(List<OutboxEntry> batch) async {
    if (batch.isEmpty) {
      return const SyncPushResult(acks: [], rejections: []);
    }
    final result = await backend.push(batch, deviceId: deviceId);
    final byId = {for (final e in batch) e.id: e};

    // ack：本地回写 revision / acked_at（§6.2 写路径末步）。
    for (final ack in result.acks) {
      await outbox.markAcked(ack.outboxId, ackedAt: ack.ackedAt);
      final entry = byId[ack.outboxId];
      if (entry != null) {
        // 服务端权威版本回写业务行（§5.1 revision「同步升级为服务端版本」）。
        await store.writeRevision(entry.tableName, entry.rowId, ack.revision);
      }
    }

    // 拒绝：分类回处理（§6.2 服务端校验清单 → 引擎侧处置）。
    for (final rejection in result.rejections) {
      final entry = byId[rejection.outboxId];
      if (entry != null) {
        await _handleRejection(entry, rejection.reason);
      }
    }
    return result;
  }

  /// 作废计数（[syncOnce] 报告用；每次 drop 递增、每轮 syncOnce 归零）。
  int _dropCounter = 0;

  /// 拒绝分类回处理（§6.2「服务端校验：schema_ver / 行存在性 / hlc 单调」）。
  ///
  /// - [SyncRejectionReason.schemaVerRejected]：本端永不理解该行 → 作废
  ///   （§6.4 前向兼容的对侧：超档载荷无法回放）；
  /// - [SyncRejectionReason.rowMissing] + delete：目标行本就不存在 = 删除
  ///   幂等完成 → 作废；+ upsert：父行未上送完成 → 暂缓保留（下轮重试，
  ///   §6.2 per-table 依赖序）；
  /// - [SyncRejectionReason.hlcNonMonotonic] / [SyncRejectionReason
  ///   .baseRevisionConflict] / [SyncRejectionReason.tombstoneConflict]：
  ///   服务端已有更新事实（LWW 后写者胜 / 乐观校验 / 墓碑胜，§6.5）→
  ///   本条出网作废，且**立即采纳服务端现值**（[_adoptServerRow]）——
  ///   裁决已发生，双端必须收敛到同一结果；等 pull 采纳会因本地 hlc 更新
  ///   而 LWW 惜败、永不收敛。
  Future<void> _handleRejection(
    OutboxEntry entry,
    SyncRejectionReason reason,
  ) async {
    switch (reason) {
      case SyncRejectionReason.schemaVerRejected:
        await outbox.drop(entry.id);
        _dropCounter += 1;
      case SyncRejectionReason.rowMissing:
        if (entry.op == OutboxOp.delete) {
          await outbox.drop(entry.id);
          _dropCounter += 1;
        }
        // upsert 父行缺失：保留待下轮（父行上送 ack 后重试成功）。
      case SyncRejectionReason.hlcNonMonotonic:
      case SyncRejectionReason.baseRevisionConflict:
      case SyncRejectionReason.tombstoneConflict:
        await outbox.drop(entry.id);
        _dropCounter += 1;
        // 采纳服务端裁决现值（§6.5：服务端是 LWW/墓碑的权威仲裁者）。
        await _adoptServerRow(entry.tableName, entry.rowId);
      case SyncRejectionReason.unknown:
        // 未知原因保守重试（自旋由 syncOnce 的批量终止条件兜底）。
        break;
    }
  }

  /// 采纳服务端单行现值（push 被拒后的收敛步，§6.2/§6.5）。
  ///
  /// 服务端已对该行完成仲裁（LWW / baseRevision / 墓碑），本端本地行即使
  /// hlc 更新也属「出网作废」的败者——直接以服务端现值覆盖（绕过本地 LWW，
  /// 服务端是权威真值）；行已不存在（幂等删除完成等）则无操作。
  Future<void> _adoptServerRow(String tableName, String rowId) async {
    final RemoteChange? remote;
    try {
      remote = await backend.fetchRow(tableName: tableName, rowId: rowId);
    } on SyncBackendException {
      // 采纳链路意外中断：不致命——下一轮 pull 会按游标重投该行并仲裁
      // （游标未必越过本行），此处仅放弃即时收敛。
      return;
    }
    if (remote == null) {
      return;
    }
    final payload = _decodePayload(remote.payload);
    if (payload == null) {
      return;
    }
    final spec = syncTableSpec(tableName);
    try {
      // 传入仲裁前本地行：金额行状态位迁移（active→superseded）等合法
      // 变迁可在采纳步直接放行（§5.2②），与 pull 侧同一判定。
      final local = await store.getRawRow(tableName, rowId);
      final outcome = await _applyWinner(
        spec,
        payload,
        deleteOp: remote.op == OutboxOp.delete,
        local: local,
      );
      // 采纳覆盖的是败者本地行，仍须给投影补脏（§5.6⑬/§6.5 末行）。
      if (outcome.dirtyDates.isNotEmpty) {
        await store.markDatesDirty(outcome.dirtyDates);
        await store.recomputeDirty();
      }
      // 采纳行的远端时间戳并入时钟（§6.3 recv：跳变跟上）。
      clock.recvEncoded(remote.hlc);
    } on _TransientSyncError {
      // 父行未到等暂态：交给下一轮 pull（游标未推进、行会重投递）。
    } on FormatException {
      // 定宽编码非法（服务端行病态）：放弃即时采纳，交 pull 侧坏载荷处理。
    }
  }

  // ── 读路径：per-table 游标增量拉取（§6.2 GET /rpc/sync_pull 半边）──────

  @override
  Future<SyncPullResult> pull(SyncPullCursors since) async {
    final remote = await backend.pull(since, deviceId: deviceId);
    final apply = await _applyRemoteChanges(remote.changes);
    // 供 syncOnce 汇总（每轮 pull 覆盖，调用方逐轮累计）。
    _lastApply = apply;

    // 游标推进（§6.2/§5.6⑰）：确定性处理完成（落库/仲裁跳过/确定性拒绝）
    // 的表推进到该表最后一条确定性 hlc；存在暂态失败的表停在其前一条，
    // 未处理行下轮重拉（幂等：重投递行经 LWW 等仲裁安全去重）。
    // W7-8 集成修复：游标单调（只进不退，与 0002_sync_rpc.sql 的
    // GREATEST(v_cursor, v_max_hlc)、InMemorySyncBackend 的 clamp 对齐）——
    // 水位补投的迟到行 hlc 低于既有游标，比较原先是「不等于」即写入，
    // 会把本地游标拉回迟到行之下，下轮 pull 以回退游标重投已投递区间
    // （§6.2 增量语义被打破）。定宽 hlc 字典序=时间序（§6.3），严格大于才推进。
    final next = <String, String>{...since};
    for (final entry in apply.cursorByTable.entries) {
      final table = entry.key;
      final advanced = entry.value;
      final current = since[table] ?? '';
      if (advanced != null && advanced.compareTo(current) > 0) {
        next[table] = advanced;
        await store.writeCursor(table, advanced);
      }
    }

    // §6.3 recv：远端时间戳并入时钟（跳变跟上；后续本地写不低于远端全序）。
    for (final change in remote.changes) {
      try {
        clock.recvEncoded(change.hlc);
      } on FormatException {
        // 定宽编码非法：行本身已按坏载荷处理（跳过），时钟不吃脏值。
      }
    }

    // day_summary 由 dirty 自愈重算（§6.5 末行「投影不同步」、§5.6⑬）。
    if (apply.dirtyDates.isNotEmpty) {
      await store.markDatesDirty(apply.dirtyDates);
    }
    await store.recomputeDirty();

    return SyncPullResult(
      changes: remote.changes,
      nextCursors: next,
      hasMore: remote.hasMore,
    );
  }

  /// 远端变更落库：按「父表→子表」依赖序（§6.2）+ 表内 hlc 升序处理；
  /// 逐行仲裁（[resolve]）→ 同一校验落库（[_applyWinner]）。
  Future<_ApplyReport> _applyRemoteChanges(List<RemoteChange> changes) async {
    final report = _ApplyReport();
    if (changes.isEmpty) {
      return report;
    }
    final byTable = <String, List<RemoteChange>>{};
    for (final change in changes) {
      byTable.putIfAbsent(change.tableName, () => []).add(change);
    }
    for (final list in byTable.values) {
      list.sort((a, b) => a.hlc.compareTo(b.hlc)); // 定宽字典序=全序（§6.3）
    }
    final orderedTables = byTable.keys.toList()
      ..sort((a, b) {
        final ra = syncTableSpec(a).rank;
        final rb = syncTableSpec(b).rank;
        final r = ra.compareTo(rb);
        if (r != 0) return r;
        return a.compareTo(b);
      });

    for (final table in orderedTables) {
      final spec = syncTableSpec(table);
      String? deterministic;
      var transient = false;
      for (final change in byTable[table]!) {
        try {
          final outcome = await _applyOne(spec, change);
          report.dirtyDates.addAll(outcome.dirtyDates);
          if (outcome.applied) {
            report.applied += 1;
          } else {
            report.skipped += 1;
          }
          deterministic = change.hlc;
        } on _TransientSyncError {
          // 暂态（父行未到等）：该表游标停在本条之前，整批未处理行重拉。
          report.deferred += 1;
          transient = true;
          break;
        }
      }
      if (!transient && deterministic != null) {
        report.cursorByTable[table] = deterministic;
      }
    }
    return report;
  }

  /// 仲裁并应用单条远端变更（§6.5 矩阵 + 「与本地写同一校验」，§6.2）。
  Future<_ApplyOutcome> _applyOne(SyncTableSpec spec, RemoteChange change) {
    return _guard(spec, change, () async {
      final payload = _decodePayload(change.payload); // 坏 JSON → 确定性跳过
      if (payload == null) {
        return const _ApplyOutcome(applied: false);
      }

      // schema_ver 协商（§6.4「同步层按 schema_ver 协商容忍 N-1」）：
      // 超档载荷本端无法理解 → 确定性拒绝（游标照常推进，不阻断后续）。
      final schemaVer = (payload['schema_ver'] as int?) ?? kCurrentSchemaVer;
      if (schemaVer > kCurrentSchemaVer) {
        return const _ApplyOutcome(applied: false);
      }
      // §5.1 公共列校验（hlc 定宽编码等）——坏数据不进仲裁。
      try {
        SyncMeta.fromRowJson(payload);
      } on FormatException {
        return const _ApplyOutcome(applied: false);
      } on ArgumentError {
        return const _ApplyOutcome(applied: false);
      }

      final rowId = change.rowId;
      final local = await store.getRawRow(spec.name, rowId);
      if (local == null) {
        // 本地无行：直接落库（依赖序已保证父行先至；父行仍缺 → 暂态）。
        return _applyWinner(
          spec,
          payload,
          deleteOp: change.op == OutboxOp.delete,
        );
      }
      final localTomb = local['deleted_at'] != null;
      final remoteTomb =
          payload['deleted_at'] != null || change.op == OutboxOp.delete;

      if (localTomb && !remoteTomb) {
        // 墓碑拒绝复活（§6.5 删除行「删后编辑保持删除胜出」）——绝对规则，
        // 本地校验直接挡下，不经 resolve。
        return const _ApplyOutcome(applied: false);
      }

      // 其余情形统一进 §6.5 矩阵仲裁（含墓碑互压与存活冲突）。
      final resolution = await resolve(
        SyncConflict(
          tableName: spec.name,
          rowId: rowId,
          conflictClass:
              (localTomb || remoteTomb) ? ConflictClass.tombstone : spec.conflictClass,
          localHlc: local['hlc'] as String,
          remoteHlc: change.hlc,
          localPayload: jsonEncode(local),
          remotePayload: jsonEncode(payload),
        ),
      );
      switch (resolution.winner) {
        case ConflictWinner.local:
          return const _ApplyOutcome(applied: false);
        case ConflictWinner.remote:
          return _applyWinner(
            spec,
            payload,
            deleteOp: remoteTomb,
            local: local,
          );
        case ConflictWinner.merged:
          return _applyWinner(
            spec,
            _decodePayload(resolution.mergedPayload!)!,
            deleteOp: remoteTomb,
            local: local,
          );
      }
    });
  }

  /// 仲裁胜者落库（「与本地写同一校验」，§6.2）。
  ///
  /// - entries / entry_lines：经 core_db 仓库（墓碑拒绝复活、金额行不可变、
  ///   投影联动——与 UI 本地写完全同路径，§5.1/§3.4/§5.6）；
  /// - 其余表：整行 upsert（[DriftSyncLocalStore.applyGenericRow]）。
  ///
  /// [local] 为仲裁前的本地行快照（无本地行传 null），用于 entry_lines 的
  /// 金额行状态位迁移判定（见 on MoneyLineImmutableException 分支）。
  Future<_ApplyOutcome> _applyWinner(
    SyncTableSpec spec,
    Map<String, Object?> payload, {
    required bool deleteOp,
    Map<String, Object?>? local,
  }) async {
    // 主键缺失属坏载荷（§5.1 id=UUIDv7 必填）——确定性跳过，不可重试自愈。
    if (payload['id'] is! String) {
      return const _ApplyOutcome(applied: false);
    }
    switch (spec.name) {
      case 'entries':
        try {
          await store.applyEntry(payload);
          return const _ApplyOutcome(applied: true);
        } on ArgumentError {
          // 领域校验不过（部分快照等）：墓碑可降级为通用部分列更新；
          // 存活行为坏载荷 → 确定性跳过。
          if (payload['deleted_at'] != null || deleteOp) {
            await store.applyGenericRow(spec, payload);
            return const _ApplyOutcome(applied: true);
          }
          return const _ApplyOutcome(applied: false);
        }
      case 'entry_lines':
        try {
          await store.applyLine(payload);
          return const _ApplyOutcome(applied: true);
        } on StateError {
          // 父事件未到（依赖序之外的散行）：暂态，游标不推进。
          throw _TransientSyncError();
        } on MoneyLineImmutableException {
          // §5.2②/§6.5：confirmed 后的 money 行不可变，但修正链的**状态位
          // 迁移**（active→superseded/void，金额事实不变）是合法变迁——
          // supersede 写旧行状态位正是修正流程的组成部分。仅当业务事实列
          // 全部一致时放行（降级为通用部分列更新）；金额事实真被改写属
          // 协议越界，本地确定性拒绝（合法路径永不触发）。
          if (local != null && _isLineStatusOnlyTransition(local, payload)) {
            await store.applyGenericRow(spec, payload);
            return const _ApplyOutcome(applied: true);
          }
          return const _ApplyOutcome(applied: false);
        } on ArgumentError {
          if (payload['deleted_at'] != null || deleteOp) {
            await store.applyGenericRow(spec, payload);
            return const _ApplyOutcome(applied: true);
          }
          return const _ApplyOutcome(applied: false);
        }
      default:
        final dates = await store.applyGenericRow(spec, payload);
        return _ApplyOutcome(applied: true, dirtyDates: dates);
    }
  }

  /// 判定 entry_lines 远端行相对本地行是否为「仅状态位/元数据迁移」：
  /// §5.2② 金额事实列全部一致（supersede/void 只改 status 与 §5.1 公共列）。
  /// 任一事实列分歧 → false（金额不可变边界仍生效）。
  static bool _isLineStatusOnlyTransition(
    Map<String, Object?> local,
    Map<String, Object?> incoming,
  ) {
    // 金额行事实列（§5.2②）：这些列在 confirmed 后任何路径都不得变。
    const factKeys = <String>[
      'entry_id',
      'type',
      'amount',
      'direction',
      'ledger_id',
      'category_id',
      'currency',
      'confidence',
      'payload',
      'correction_of',
    ];
    for (final key in factKeys) {
      final a = local[key];
      final b = incoming[key];
      if (a is num && b is num) {
        if ((a - b).abs() > 1e-9) {
          return false;
        }
      } else if (a != b) {
        return false;
      }
    }
    return true;
  }

  /// 把 [_applyWinner]/仲裁过程抛出的领域异常翻译成两类：暂态（重拉）与
  /// 确定性（跳过）。[body] 内已分类；此处兜底意外异常按暂态处理。
  Future<_ApplyOutcome> _guard(
    SyncTableSpec spec,
    RemoteChange change,
    Future<_ApplyOutcome> Function() body,
  ) async {
    try {
      return await body();
    } on _TransientSyncError {
      rethrow;
    } on StateError {
      // 仓库层其余 StateError（如父行缺失变体）按暂态重拉。
      throw _TransientSyncError();
    } on ArgumentError {
      // 意外参数错：保守按暂态重拉一次，避免误跳过。
      throw _TransientSyncError();
    } on FormatException {
      // 编码类错误不可自愈：确定性跳过。
      return const _ApplyOutcome(applied: false);
    }
  }

  Map<String, Object?>? _decodePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  // ── 冲突仲裁：§6.5 矩阵 ───────────────────────────────────────────────

  @override
  Future<SyncConflictResolution> resolve(SyncConflict conflict) async {
    switch (conflict.conflictClass) {
      case ConflictClass.scalarLww:
      case ConflictClass.entryLww:
      case ConflictClass.facetRowLww:
      case ConflictClass.immutableMoney:
      case ConflictClass.appendOnly:
        // 行级 LWW（§6.5 第 1/2/3 行）：hlc 大者胜，同刻 device_id 决胜——
        // 定宽编码下字符串字典序即全序（§6.3）。append-only 的「并集」指
        // 不同行并存（结构层免冲突）；同 id 行分歧按 LWW 兜底。
        final cmp = conflict.remoteHlc.compareTo(conflict.localHlc);
        return SyncConflictResolution(
          winner: cmp > 0 ? ConflictWinner.remote : ConflictWinner.local,
        );

      case ConflictClass.todoDoneForward:
        // 完成事件只前进（§6.5 第 6 行）：并发 set vs unset → set 胜
        // （勾选永不丢失）；取消完成仅无并发时生效。合并=双方 done_at 的
        // 「只前进」并（非空者中取大），其余字段随 LWW 胜者。
        final local = jsonDecode(conflict.localPayload) as Map<String, Object?>;
        final remote =
            jsonDecode(conflict.remotePayload) as Map<String, Object?>;
        final mergedDoneAt = _mergeDoneAt(local['done_at'], remote['done_at']);
        final cmp = conflict.remoteHlc.compareTo(conflict.localHlc);
        final base = cmp > 0 ? remote : local;
        final merged = <String, Object?>{...base, 'done_at': mergedDoneAt};
        return SyncConflictResolution(
          winner: ConflictWinner.merged,
          mergedPayload: jsonEncode(merged),
        );

      case ConflictClass.tombstone:
        // 墓碑拒绝复活（§6.5 第 7 行）：任一方为墓碑 → 删除胜出
        // （「删后编辑保持删除胜出」，与 hlc 新旧无关）；双方皆墓碑 → LWW。
        final local = jsonDecode(conflict.localPayload) as Map<String, Object?>;
        final remote =
            jsonDecode(conflict.remotePayload) as Map<String, Object?>;
        final localTomb = local['deleted_at'] != null;
        final remoteTomb = remote['deleted_at'] != null;
        if (localTomb && !remoteTomb) {
          return const SyncConflictResolution(winner: ConflictWinner.local);
        }
        if (remoteTomb && !localTomb) {
          return const SyncConflictResolution(winner: ConflictWinner.remote);
        }
        final cmp = conflict.remoteHlc.compareTo(conflict.localHlc);
        return SyncConflictResolution(
          winner: cmp > 0 ? ConflictWinner.remote : ConflictWinner.local,
        );
    }
  }

  /// done_at 只前进合并（§6.5 todo 行、§5.5⑩）：任一方 set 即非空；
  /// 双方 set 取较大者（完成时刻单调不减）。
  static int? _mergeDoneAt(Object? a, Object? b) {
    final av = a is int ? a : null;
    final bv = b is int ? b : null;
    if (av == null) {
      return bv;
    }
    if (bv == null) {
      return av;
    }
    return math.max(av, bv);
  }

  // ── 编排：一轮完整同步（push 循环 → pull 循环 → 投影自愈）──────────────

  /// 一轮完整同步（§6.2 触发时机=启动即拉/前台切回/15 分钟兜底的执行体）。
  ///
  /// 本地优先（§6.1 原则 1）：分区/断网只写 [SyncCycleReport.error] 并发
  /// error 状态，永不抛出、永不阻塞；outbox 保持待发、重试幂等。
  Future<SyncCycleReport> syncOnce({
    int? outboxBatchSize,
    int maxPushRounds = 10,
  }) async {
    final batchLimit = outboxBatchSize ?? maxOutboxBatchSize;
    final counts = _CycleCounts();
    _dropCounter = 0;
    Object? error;
    await _emit(SyncPhase.pushing);
    try {
      // push 循环（§6.2「后台出队」）：每轮要么清账（ack/作废减少 pending）
      // 要么整体暂缓终止，绝不自旋。
      for (var round = 0; round < maxPushRounds; round++) {
        final batch = await outbox.dequeuePending(limit: batchLimit);
        if (batch.isEmpty) {
          break;
        }
        final result = await push(batch);
        counts.pushed += batch.length;
        counts.acked += result.acks.length;
        for (final rejection in result.rejections) {
          counts.rejections[rejection.reason] =
              (counts.rejections[rejection.reason] ?? 0) + 1;
        }
        final pending = await outbox.pendingCount();
        if (pending == 0) {
          break;
        }
        // 本批全部暂缓（无 ack、无作废）→ 本轮不再推进，等下一触发。
        final allDeferred = result.acks.isEmpty &&
            result.rejections.isNotEmpty &&
            result.rejections.every(
              (r) =>
                  r.reason == SyncRejectionReason.rowMissing ||
                  r.reason == SyncRejectionReason.unknown,
            );
        if (allDeferred) {
          break;
        }
      }
      counts.dropped = _dropCounter;
    } catch (e) {
      error = e;
      counts.dropped = _dropCounter;
      await _emitError(e);
      return _buildReport(counts, error);
    }

    await _emit(SyncPhase.pulling);
    try {
      var cursors = await store.readCursors();
      var rounds = 0;
      var hasMore = true;
      while (hasMore && rounds < maxPullRounds) {
        final result = await pull(cursors);
        cursors = result.nextCursors;
        hasMore = result.hasMore;
        rounds++;
        counts.pulled += result.changes.length;
        // 每轮落库结论累计（§6.2：分批续拉直到 hasMore=false）。
        final apply = _lastApply!;
        counts.applied += apply.applied;
        counts.skipped += apply.skipped;
        counts.deferred += apply.deferred;
        counts.dirtyDates.addAll(apply.dirtyDates);
      }
      counts.cursors.addAll(cursors);
    } catch (e) {
      error = e;
      await _emitError(e);
      return _buildReport(counts, error);
    }

    await _emit(SyncPhase.done);
    return _buildReport(counts, error);
  }

  _ApplyReport? _lastApply;

  SyncCycleReport _buildReport(_CycleCounts counts, Object? error) =>
      SyncCycleReport(
        pushed: counts.pushed,
        acked: counts.acked,
        rejections: Map.unmodifiable(counts.rejections),
        droppedOutbox: counts.dropped,
        pulled: counts.pulled,
        applied: counts.applied,
        skipped: counts.skipped,
        deferred: counts.deferred,
        cursors: Map.unmodifiable(counts.cursors),
        dirtyDates: Set.unmodifiable(counts.dirtyDates),
        error: error,
      );

  /// 当前未确认出网条数（顶栏小圆点数据源，§6.1）。
  Future<int> pendingOutboxCount() => outbox.pendingCount();

  Future<void> _emit(SyncPhase phase) async {
    final listener = this.listener;
    if (listener == null) {
      return;
    }
    listener(
      SyncStatus(
        phase: phase,
        pending: await outbox.pendingCount(),
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _emitError(Object error) async {
    final listener = this.listener;
    if (listener == null) {
      return;
    }
    listener(
      SyncStatus(
        phase: SyncPhase.error,
        pending: await outbox.pendingCount(),
        error: error.toString(),
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

/// 单轮同步的累计器。
class _CycleCounts {
  int pushed = 0;
  int acked = 0;
  int dropped = 0;
  int pulled = 0;
  int applied = 0;
  int skipped = 0;
  int deferred = 0;
  final Map<SyncRejectionReason, int> rejections = {};
  final Map<String, String> cursors = {};
  final Set<String> dirtyDates = {};
}

/// 单批远端变更的落库结论。
class _ApplyReport {
  final Map<String, String?> cursorByTable = {};
  final Set<String> dirtyDates = {};
  int applied = 0;
  int skipped = 0;
  int deferred = 0;
}

/// 单行仲裁落库结论。
class _ApplyOutcome {
  final bool applied;
  final Set<String> dirtyDates;
  const _ApplyOutcome({required this.applied, this.dirtyDates = const {}});
}

/// 暂态失败（父行未到等）：本表游标不推进，重拉重试。
class _TransientSyncError implements Exception {
  const _TransientSyncError();
}
