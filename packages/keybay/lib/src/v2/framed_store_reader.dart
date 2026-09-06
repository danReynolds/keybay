part of 'keybay_v2.dart';

/// Common V2 transaction engine for one resolved application store.
///
/// It owns host resolution and initialization; each returned session remains
/// the sole owner of its store key and operation queue. Production and tests
/// differ only in which [HostPlatform] supplies the resolved binding.
final class V2StoreEngine {
  V2StoreEngine(
    this._platform, {
    V2EntropySource? entropy,
    V2PassphraseDeriver? passphraseDeriver,
  }) : _entropy = entropy ?? SecureV2EntropySource(),
       _passphraseDeriver = passphraseDeriver ?? Argon2idV2PassphraseDeriver(),
       _testProbe = null;

  /// Creates an engine with deterministic secret-cleanup observations.
  ///
  /// This constructor and [V2StoreEngineTestProbe] are internal test seams;
  /// neither is exported by the package API.
  V2StoreEngine.debug(
    this._platform,
    this._testProbe, {
    V2EntropySource? entropy,
    V2PassphraseDeriver? passphraseDeriver,
  }) : _entropy = entropy ?? SecureV2EntropySource(),
       _passphraseDeriver = passphraseDeriver ?? Argon2idV2PassphraseDeriver();

  final HostPlatform _platform;
  final V2EntropySource _entropy;
  final V2PassphraseDeriver _passphraseDeriver;
  final V2StoreEngineTestProbe? _testProbe;
  Future<ResolvedHost>? _resolvedHost;
  final List<WeakReference<V2StoreSession>> _sessions =
      <WeakReference<V2StoreSession>>[];
  int _runtimeGeneration = 0;

  /// Opens or initializes the store without reading record values.
  Future<V2StoreSession> open({KeybayCredential? credential}) =>
      _withCredential(credential, _open);

  /// Compatibility spelling for platform-only M4/M5 qualification tests.
  Future<V2StoreSession> openPlatformOnly() => open();

  Future<V2StoreSession> _open(_CredentialSnapshot? credential) => _future(
    () async {
      PinnedStoreFile? pin;
      PlatformRootLease? lease;
      Uint8List? storeKey;
      Uint8List? storeId;
      Object? primaryFailure;
      StackTrace? primaryStack;
      V2StoreSession? session;
      var wasInitialized = false;
      var existingWasAuthenticated = false;
      var openingGeneration = 0;
      try {
        final host = await _resolveHost();
        Future<void> authenticateExisting() async {
          final openedPin = pin!;
          final prefix = await _readPrefix(openedPin);
          final state = ProviderState(prefix.bootstrap.core.providerState);
          final openedLease = await host.protector.openExisting(
            state,
            interaction: PlatformInteraction.allowed,
          );
          if (openedLease == null) {
            throw _error(
              KeybayErrorCode.platformKeyInvalidated,
              'The platform protection key is unavailable.',
            );
          }
          lease = openedLease;
          if (!openedLease.providerState.hasSameBytes(state)) {
            throw _error(
              KeybayErrorCode.platformKeyInvalidated,
              'The platform protection state changed while opening.',
            );
          }

          final domain = host.binding.domain.copyBytes();
          final aad = encodePlatformPackageAad(
            storageDomain: domain,
            bootstrapCore: prefix.bootstrap.core,
          );
          Uint8List? plaintext;
          V2KeyPackage? package;
          try {
            plaintext = await openedLease.openPackage(
              sealedPackage: prefix.sealedPackage,
              aad: aad,
            );
            package = decodeKeyPackage(plaintext);
            switch (package) {
              case V2PlatformOnlyPackage():
                if (credential != null) {
                  throw _error(
                    KeybayErrorCode.protectionMismatch,
                    'The existing store does not use the supplied credential.',
                  );
                }
                storeId = package.storeId;
                storeKey = package.takeStoreKey();
                session = V2StoreSession._(
                  engine: this,
                  host: host,
                  storeKey: storeKey!,
                  storeId: storeId!,
                  epoch: package.epoch,
                  passphraseMethodId: null,
                  wasInitialized: false,
                  runtimeGeneration: openingGeneration,
                  entropy: _entropy,
                  testProbe: _testProbe,
                );
              case V2PassphrasePackage():
                if (credential == null) {
                  throw _error(
                    KeybayErrorCode.authRequired,
                    'This store requires an additional credential.',
                  );
                }
                storeId = package.storeId;
                final methodId = package.methodId;
                final salt = package.salt;
                final innerEnvelope = package.innerEnvelope;
                Uint8List? passphraseKey;
                try {
                  passphraseKey = await _derivePassphraseAndReleaseCredential(
                    deriver: _passphraseDeriver,
                    credential: credential,
                    profileId: package.profileId,
                    salt: salt,
                  );
                  try {
                    storeKey = await openPassphraseEnvelope(
                      passphraseKey: passphraseKey,
                      storeId: storeId!,
                      epoch: package.epoch,
                      methodId: methodId,
                      profileId: package.profileId,
                      salt: salt,
                      innerEnvelope: innerEnvelope,
                    );
                  } on V2CryptoFailure {
                    throw _error(
                      KeybayErrorCode.unlockFailed,
                      'The supplied credential did not unlock the store.',
                    );
                  }
                  session = V2StoreSession._(
                    engine: this,
                    host: host,
                    storeKey: storeKey!,
                    storeId: storeId!,
                    epoch: package.epoch,
                    passphraseMethodId: encodeMethodId(methodId),
                    wasInitialized: false,
                    runtimeGeneration: openingGeneration,
                    entropy: _entropy,
                    testProbe: _testProbe,
                  );
                } finally {
                  if (passphraseKey != null) _clear(passphraseKey);
                }
            }
          } finally {
            package?.clear();
            if (plaintext != null) _clear(plaintext);
          }
        }

        await host.files.withExclusiveTransaction((transaction) async {
          openingGeneration = _runtimeGeneration;
          final artifacts = await transaction.observeArtifacts();
          if (artifacts.hasTransactionArtifacts && !artifacts.hasLiveFile) {
            throw _error(
              KeybayErrorCode.storeStateConflict,
              'The V2 store has incomplete transaction state.',
            );
          }
          if (artifacts.hasLiveFile) {
            pin = await _openPin(transaction.openPinnedLive);
            if (artifacts.hasTransactionArtifacts) {
              await authenticateExisting();
              await transaction.discardAbandonedStaging();
              existingWasAuthenticated = true;
            }
            return;
          }
          final initialized = await _initializeStore(
            host,
            transaction,
            credential,
          );
          storeKey = initialized.storeKey;
          storeId = initialized.storeId;
          session = V2StoreSession._(
            engine: this,
            host: host,
            storeKey: storeKey!,
            storeId: storeId!,
            epoch: initialized.epoch,
            passphraseMethodId: initialized.passphraseMethodId,
            wasInitialized: true,
            runtimeGeneration: openingGeneration,
            entropy: _entropy,
            testProbe: _testProbe,
          );
          wasInitialized = true;
        });
        if (!wasInitialized && !existingWasAuthenticated) {
          await authenticateExisting();
        }
      } on Object catch (error, stackTrace) {
        primaryFailure = _mapReaderFailure(error);
        primaryStack = stackTrace;
      }

      final acquiredPin = pin;
      final cleanupFailure = acquiredPin == null
          ? null
          : await _closeOpenResources(lease, acquiredPin);
      final failure = primaryFailure ?? cleanupFailure;
      if (failure != null || openingGeneration != _runtimeGeneration) {
        final failedSession = session;
        failedSession?._clearKeyMaterial();
        if (failedSession != null) {
          _testProbe?._recordFailedOpen(failedSession);
        } else {
          final failedStoreKey = storeKey;
          final failedStoreId = storeId;
          if (failedStoreKey != null) _clear(failedStoreKey);
          if (failedStoreId != null) _clear(failedStoreId);
        }
        Error.throwWithStackTrace(
          failure ??
              _error(
                KeybayErrorCode.staleSession,
                'The store was reset while it was being opened.',
              ),
          primaryStack ?? StackTrace.current,
        );
      }
      _register(session!);
      return session!;
    },
  );

  /// Removes this resolved application's qualified V2 state.
  Future<void> reset() => _future(_resetPlatformState);

  /// Shares an in-flight or successful host resolution without making a
  /// transient platform failure permanent for this isolate.
  Future<ResolvedHost> _resolveHost() {
    final resolved = _resolvedHost;
    if (resolved != null) return resolved;

    late final Future<ResolvedHost> pending;
    pending = Future<ResolvedHost>.sync(_platform.resolve).then(
      (host) => host,
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_resolvedHost, pending)) _resolvedHost = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _resolvedHost = pending;
    return pending;
  }

  void _register(V2StoreSession session) {
    _sessions.removeWhere((reference) => reference.target == null);
    _sessions.add(WeakReference<V2StoreSession>(session));
  }

  Future<void> _invalidateSessions() async {
    _runtimeGeneration++;
    final draining = <Future<void>>[];
    _sessions.removeWhere((reference) {
      final session = reference.target;
      if (session == null) return true;
      draining.add(session._invalidate());
      return false;
    });
    await Future.wait<void>(draining);
  }

  Future<void> _invalidatePeerSessions(V2StoreSession owner) async {
    final draining = <Future<void>>[];
    _sessions.removeWhere((reference) {
      final session = reference.target;
      if (session == null) return true;
      if (!identical(session, owner)) {
        draining.add(session._invalidate());
      }
      return false;
    });
    await Future.wait<void>(draining);
  }

  Future<void> _advanceRotationGeneration(V2StoreSession owner) {
    _runtimeGeneration++;
    owner._runtimeGeneration = _runtimeGeneration;
    return _invalidatePeerSessions(owner);
  }

  Future<void> _abandonRotationGeneration(V2StoreSession owner) {
    _runtimeGeneration++;
    return _invalidatePeerSessions(owner);
  }
}

/// An authenticated handle to one application store.
///
/// It retains only the store key, store identifier, epoch, and resolved host.
/// Every operation pins and authenticates a fresh complete file generation;
/// manifests, record names, values, and file handles are never cached.
/// It is the sole owner of its key material, operation queue, invalidation,
/// and close lifecycle; the production runtime must not wrap it in a second
/// session owner.
final class V2StoreSession implements KeybaySession {
  V2StoreSession._({
    required V2StoreEngine engine,
    required ResolvedHost host,
    required Uint8List storeKey,
    required Uint8List storeId,
    required int epoch,
    required String? passphraseMethodId,
    required this.wasInitialized,
    required int runtimeGeneration,
    required V2EntropySource entropy,
    required V2StoreEngineTestProbe? testProbe,
  }) : _engine = engine,
       _host = host,
       _storeKey = storeKey,
       _storeId = storeId,
       _epoch = epoch,
       _passphraseMethodId = passphraseMethodId,
       _runtimeGeneration = runtimeGeneration,
       _entropy = entropy,
       _testProbe = testProbe {
    auth = _V2AuthManager(this);
  }

  final V2StoreEngine _engine;
  final ResolvedHost _host;
  Future<void> _operationTail = Future<void>.value();
  Uint8List _storeKey;
  final Uint8List _storeId;
  int _epoch;
  String? _passphraseMethodId;
  int _runtimeGeneration;
  final V2EntropySource _entropy;
  final V2StoreEngineTestProbe? _testProbe;
  @override
  final bool wasInitialized;
  @override
  late final KeybayAuthManager auth;
  _SessionLifecycle _lifecycle = _SessionLifecycle.open;
  bool _invalidated = false;
  Future<void>? _closing;

  @override
  bool get isClosed => _lifecycle != _SessionLifecycle.open;

  @override
  Future<String?> get(String key) => _prepare(() {
    final requested = _prepareKeys(<String>[key]);
    return _start(() async {
      final values = await _readMany(requested);
      final bytes = values[key];
      if (bytes == null) return null;
      try {
        try {
          return utf8.decode(bytes, allowMalformed: false);
        } on FormatException {
          throw _error(
            KeybayErrorCode.invalidRecordEncoding,
            'The requested record is not valid UTF-8.',
          );
        }
      } finally {
        _clear(bytes);
      }
    }, ownedInputs: [for (final item in requested) item.bytes]);
  });

  @override
  Future<Uint8List?> getBytes(String key) => _prepare(() {
    final requested = _prepareKeys(<String>[key]);
    return _start(
      () async => (await _readMany(requested))[key],
      ownedInputs: [for (final item in requested) item.bytes],
    );
  });

  @override
  Future<Map<String, Uint8List?>> getManyBytes(Iterable<String> keys) =>
      _prepare(() {
        final requested = _prepareKeys(keys);
        return _start(() {
          if (requested.isEmpty) {
            return Map<String, Uint8List?>.unmodifiable(<String, Uint8List?>{});
          }
          return _readMany(requested);
        }, ownedInputs: [for (final item in requested) item.bytes]);
      });

  @override
  Future<List<String>> listKeys() =>
      _prepare(() => _start(_readAuthenticatedKeys));

  @override
  Future<bool> contains(String key) => _prepare(() {
    final requested = _prepareKeys(<String>[key]);
    return _start(
      () => _contains(requested.single),
      ownedInputs: [for (final item in requested) item.bytes],
    );
  });

  @override
  Future<void> set(String key, String value) => _prepare(() {
    _validateRecordKey(key);
    _validateRecordString(value);
    final bytes = Uint8List.fromList(utf8.encode(value));
    final requested = _RequestedRecord(
      key: key,
      bytes: Uint8List.fromList(key.codeUnits),
    );
    return _start(() async {
      await _commitRecordChange(this, _RecordChange.set(requested, bytes));
    }, ownedInputs: [requested.bytes, bytes]);
  });

  @override
  Future<void> setBytes(String key, Uint8List value) => _prepare(() {
    _validateRecordKey(key);
    _validateRecordValueLength(value.length);
    final bytes = Uint8List.fromList(value);
    final requested = _RequestedRecord(
      key: key,
      bytes: Uint8List.fromList(key.codeUnits),
    );
    return _start(() async {
      await _commitRecordChange(this, _RecordChange.set(requested, bytes));
    }, ownedInputs: [requested.bytes, bytes]);
  });

  @override
  Future<bool> delete(String key) => _prepare(() {
    final requested = _prepareKeys(<String>[key]);
    return _start(
      () async => (await _commitRecordChange(
        this,
        _RecordChange.delete(requested.single),
      ))!,
      ownedInputs: [for (final item in requested) item.bytes],
    );
  });

  @override
  Future<void> clearAll() => _prepare(
    () => _start(() async {
      await _commitRecordChange(this, const _RecordChange.clear());
    }),
  );

  Future<List<AuthMethod>> _listAuth() => _prepare(
    () => _start(() async {
      // Authenticate the current generation so a session rotated by
      // another engine cannot return cached policy metadata.
      await _readMany(const <_RequestedRecord>[]);
      final id = _passphraseMethodId;
      if (id == null) return const <AuthMethod>[];
      return List<AuthMethod>.unmodifiable(<AuthMethod>[
        PassphraseMethod._(id),
      ]);
    }),
  );

  Future<AuthMethod> _addAuth(KeybayCredential credential) =>
      _withCredentialOperation(
        credential,
        (snapshot) async => PassphraseMethod._(
          (await _commitAuthChange(
            this,
            _AuthChange.add,
            credential: snapshot,
          ))!,
        ),
      );

  Future<AuthMethod> _updateAuth(KeybayCredential replacement) =>
      _withCredentialOperation(
        replacement,
        (snapshot) async => PassphraseMethod._(
          (await _commitAuthChange(
            this,
            _AuthChange.update,
            credential: snapshot,
          ))!,
        ),
      );

  Future<void> _removeAuth(String id) => _prepare(
    () => _start(() async {
      await _commitAuthChange(this, _AuthChange.remove, methodId: id);
    }),
  );

  Future<T> _withCredentialOperation<T>(
    KeybayCredential credential,
    Future<T> Function(_CredentialSnapshot snapshot) operation,
  ) => _prepare(() {
    final snapshot = _snapshotCredential(credential)!;
    return _start(() => operation(snapshot), ownedInputs: [snapshot.bytes]);
  });

  void _adoptRotation({
    required Uint8List storeKey,
    required int epoch,
    required String? passphraseMethodId,
  }) {
    final previous = _storeKey;
    _storeKey = storeKey;
    _epoch = epoch;
    _passphraseMethodId = passphraseMethodId;
    _clear(previous);
  }

  Future<Map<String, Uint8List?>> _readMany(
    List<_RequestedRecord> requested,
  ) async {
    Map<String, Uint8List?>? ownedResults;
    Object? primaryFailure;
    StackTrace? primaryStack;
    PinnedStoreFile? pin;
    try {
      pin = await _openPin(_host.files.openPinnedLive);
      final generation = await _openAuthenticatedGeneration(
        host: _host,
        pin: pin,
        storeKey: _storeKey,
        storeId: _storeId,
      );
      try {
        final selected = _selectRanges(generation.ranges, requested);
        ownedResults = <String, Uint8List?>{
          for (final item in requested) item.key: null,
        };
        for (final selection in selected) {
          final frame = await _readExact(
            pin,
            offset:
                generation.layout.frameRegionOffset + selection.range.offset,
            length: selection.range.length,
          );
          final digest = digestFrame(frame);
          if (!selection.range.entry.hasFrameDigest(digest)) {
            throw _error(
              KeybayErrorCode.storeAuthenticationFailed,
              'A selected record frame failed authentication.',
            );
          }
          final keyBytes = selection.range.entry.copyKeyBytes();
          try {
            ownedResults[selection.request.key] = await openRecordFrameBytes(
              storeKey: _storeKey,
              storeId: _storeId,
              epoch: _epoch,
              keyBytes: keyBytes,
              sealedFrame: frame,
            );
          } finally {
            _clear(keyBytes);
          }
        }
      } finally {
        generation.clear();
      }
    } on Object catch (error, stackTrace) {
      primaryFailure = _mapReaderFailure(error);
      primaryStack = stackTrace;
    }

    final cleanupFailure = pin == null ? null : await _closePin(pin);
    final failure = primaryFailure ?? cleanupFailure;
    if (failure != null) {
      _clearResults(ownedResults, _testProbe);
      Error.throwWithStackTrace(failure, primaryStack ?? StackTrace.current);
    }
    return Map<String, Uint8List?>.unmodifiable(ownedResults!);
  }

  Future<bool> _contains(_RequestedRecord requested) async {
    PinnedStoreFile? pin;
    Object? primaryFailure;
    StackTrace? primaryStack;
    var found = false;
    try {
      pin = await _openPin(_host.files.openPinnedLive);
      final generation = await _openAuthenticatedGeneration(
        host: _host,
        pin: pin,
        storeKey: _storeKey,
        storeId: _storeId,
      );
      try {
        found = _findRange(generation.ranges, requested.bytes) != null;
      } finally {
        generation.clear();
      }
    } on Object catch (error, stackTrace) {
      primaryFailure = _mapReaderFailure(error);
      primaryStack = stackTrace;
    }

    final cleanupFailure = pin == null ? null : await _closePin(pin);
    final failure = primaryFailure ?? cleanupFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, primaryStack ?? StackTrace.current);
    }
    return found;
  }

  Future<List<String>> _readAuthenticatedKeys() async {
    final ownedKeys = <Uint8List>[];
    PinnedStoreFile? pin;
    Object? primaryFailure;
    StackTrace? primaryStack;
    try {
      pin = await _openPin(_host.files.openPinnedLive);
      final generation = await _openAuthenticatedGeneration(
        host: _host,
        pin: pin,
        storeKey: _storeKey,
        storeId: _storeId,
      );
      try {
        for (final entry in generation.manifest.entries) {
          ownedKeys.add(entry.copyKeyBytes());
        }
      } finally {
        generation.clear();
      }
    } on Object catch (error, stackTrace) {
      primaryFailure = _mapReaderFailure(error);
      primaryStack = stackTrace;
    }

    final cleanupFailure = pin == null ? null : await _closePin(pin);
    final failure = primaryFailure ?? cleanupFailure;
    if (failure != null) {
      for (final key in ownedKeys) {
        _clear(key);
      }
      Error.throwWithStackTrace(failure, primaryStack ?? StackTrace.current);
    }

    try {
      return List<String>.unmodifiable(ownedKeys.map(String.fromCharCodes));
    } finally {
      for (final key in ownedKeys) {
        _clear(key);
      }
    }
  }

  List<_SelectedRecord> _selectRanges(
    List<V2FrameRange> ranges,
    List<_RequestedRecord> requested,
  ) {
    final selected = <_SelectedRecord>[];
    var resultLimit = 0;
    for (final request in requested) {
      final match = _findRange(ranges, request.bytes);
      if (match == null) continue;
      resultLimit += match.length - V2StoreLimits.sealedFrameOverhead;
      if (resultLimit > V2StoreLimits.getManyResultBytes) {
        throw _error(
          KeybayErrorCode.limitExceeded,
          'The getManyBytes result limit was exceeded.',
        );
      }
      selected.add(_SelectedRecord(request: request, range: match));
    }
    return selected;
  }

  V2FrameRange? _findRange(List<V2FrameRange> ranges, List<int> requested) {
    var lower = 0;
    var upper = ranges.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      final comparison = ranges[middle].entry.compareKeyBytes(requested);
      if (comparison < 0) {
        lower = middle + 1;
      } else if (comparison > 0) {
        upper = middle;
      } else {
        return ranges[middle];
      }
    }
    return null;
  }

  List<_RequestedRecord> _prepareKeys(Iterable<String> keys) {
    final requested = <_RequestedRecord>[];
    final seen = <String>{};
    var consumed = 0;
    try {
      for (final key in keys) {
        consumed++;
        if (consumed > V2StoreLimits.getManyInputs) {
          throw _error(
            KeybayErrorCode.limitExceeded,
            'The getManyBytes input limit was exceeded.',
          );
        }
        _validateRecordKey(key);
        if (seen.add(key)) {
          requested.add(
            _RequestedRecord(
              key: key,
              bytes: Uint8List.fromList(key.codeUnits),
            ),
          );
        }
      }
      return requested;
    } catch (_) {
      for (final item in requested) {
        _clear(item.bytes);
      }
      rethrow;
    }
  }

  Future<T> _prepare<T>(Future<T> Function() operation) {
    try {
      _ensureAccepting();
      return operation();
    } on Object catch (error, stackTrace) {
      return Future<T>.error(error, stackTrace);
    }
  }

  /// Takes ownership of input copies until completion, including rejection
  /// before the queued callback runs. Cleanup precedes both the result and the
  /// queue tail observed by close, reset, and peer-session invalidation.
  Future<T> _start<T>(
    FutureOr<T> Function() operation, {
    List<Uint8List> ownedInputs = const [],
  }) {
    try {
      for (final input in ownedInputs) {
        _testProbe?.onOperationInput?.call(input);
      }
      _ensureAccepting();
      final result = _operationTail.then<T>((_) async {
        try {
          try {
            _ensureRunnable();
            return await Future<T>.sync(operation);
          } finally {
            _clearBuffers(ownedInputs);
          }
        } on KeybayException catch (error, stackTrace) {
          if (error.code == KeybayErrorCode.storeAuthenticationFailed &&
              await _hasNewerAuthenticatedGeneration()) {
            _invalidateImmediately();
            Error.throwWithStackTrace(
              _error(
                KeybayErrorCode.staleSession,
                'The Keybay session is stale.',
              ),
              stackTrace,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      });
      // Each operation keeps its own failure; later work and close only wait
      // for completion, including input cleanup.
      _operationTail = result.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      );
      return result;
    } on Object {
      _clearBuffers(ownedInputs);
      rethrow;
    }
  }

  void _ensureAccepting() {
    if (_lifecycle != _SessionLifecycle.open) {
      throw _error(
        KeybayErrorCode.sessionClosed,
        'The Keybay session is closed.',
      );
    }
    _ensureCurrent();
  }

  void _ensureRunnable() {
    if (_lifecycle == _SessionLifecycle.closed) {
      throw _error(
        KeybayErrorCode.sessionClosed,
        'The Keybay session is closed.',
      );
    }
    _ensureCurrent();
  }

  void _ensureCurrent() {
    if (_invalidated || _runtimeGeneration != _engine._runtimeGeneration) {
      throw _error(
        KeybayErrorCode.staleSession,
        'The Keybay session is stale.',
      );
    }
  }

  /// Distinguishes a genuinely damaged current generation from a rotation by
  /// another engine. This diagnostic path never asks for a credential and the
  /// provider acquisition explicitly forbids UI, including on its lease.
  Future<bool> _hasNewerAuthenticatedGeneration() async {
    try {
      return await _host.files.withExclusiveTransaction((transaction) async {
        final artifacts = await transaction.observeArtifacts();
        if (!artifacts.hasLiveFile) return true;
        if (artifacts.hasTransactionArtifacts) return false;

        final pin = await transaction.openPinnedLive();
        if (pin == null) return true;
        PlatformRootLease? lease;
        V2KeyPackage? package;
        Uint8List? plaintext;
        try {
          final prefix = await _readPrefix(pin);
          final state = ProviderState(prefix.bootstrap.core.providerState);
          lease = await _host.protector.openExisting(
            state,
            interaction: PlatformInteraction.forbidden,
          );
          if (lease == null || !lease.providerState.hasSameBytes(state)) {
            return false;
          }
          final domain = _host.binding.domain.copyBytes();
          final aad = encodePlatformPackageAad(
            storageDomain: domain,
            bootstrapCore: prefix.bootstrap.core,
          );
          plaintext = await lease.openPackage(
            sealedPackage: prefix.sealedPackage,
            aad: aad,
          );
          package = decodeKeyPackage(plaintext);
          final packageStoreId = package.storeId;

          // Only a newer epoch under the same authenticated store identity is
          // positive evidence of rotation. Replacement, rollback, and
          // same-epoch policy changes remain indistinguishable from tamper.
          return _constantTimeEquals(packageStoreId, _storeId) &&
              package.epoch > _epoch;
        } on Object {
          return false;
        } finally {
          package?.clear();
          if (plaintext != null) _clear(plaintext);
          if (lease != null) {
            try {
              await lease.close();
            } on Object {
              // Classification is best-effort and never replaces the failure.
            }
          }
          await _closePin(pin);
        }
      });
    } on Object {
      return false;
    }
  }

  @override
  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing;

    _lifecycle = _SessionLifecycle.closing;
    final completer = Completer<void>();
    _closing = completer.future;
    unawaited(_finishClose(completer));
    return completer.future;
  }

  Future<void> _finishClose(Completer<void> completer) async {
    try {
      await _operationTail;
    } on Object {
      // The originating operation future owns its error.
    } finally {
      _clearKeyMaterial();
      _lifecycle = _SessionLifecycle.closed;
      completer.complete();
    }
  }

  void _clearKeyMaterial() {
    _clear(_storeKey);
    _clear(_storeId);
  }

  Future<void> _invalidate() async {
    if (_invalidated) return _operationTail;
    _invalidated = true;
    await _operationTail;
    _clearKeyMaterial();
  }

  void _invalidateImmediately() {
    if (_invalidated) return;
    _invalidated = true;
    _clearKeyMaterial();
  }
}

final class _V2AuthManager implements KeybayAuthManager {
  const _V2AuthManager(this._session);

  final V2StoreSession _session;

  @override
  Future<List<AuthMethod>> list() => _session._listAuth();

  @override
  Future<AuthMethod> add(KeybayCredential credential) =>
      _session._addAuth(credential);

  @override
  Future<AuthMethod> update(KeybayCredential replacement) =>
      _session._updateAuth(replacement);

  @override
  Future<void> remove(String id) => _session._removeAuth(id);
}

final class _RequestedRecord {
  const _RequestedRecord({required this.key, required this.bytes});

  final String key;
  final Uint8List bytes;
}

final class _SelectedRecord {
  const _SelectedRecord({required this.request, required this.range});

  final _RequestedRecord request;
  final V2FrameRange range;
}

final class _StorePrefix {
  const _StorePrefix({required this.bootstrap, required this.sealedPackage});

  final V2Bootstrap bootstrap;
  final Uint8List sealedPackage;
}

final class _OpenedGeneration {
  const _OpenedGeneration({
    required this.prefix,
    required this.layout,
    required this.manifest,
    required this.ranges,
  });

  final _StorePrefix prefix;
  final V2StoreLayout layout;
  final V2Manifest manifest;
  final List<V2FrameRange> ranges;

  void clear() {
    manifest.clear();
  }
}

Future<_OpenedGeneration> _openAuthenticatedGeneration({
  required ResolvedHost host,
  required PinnedStoreFile pin,
  required Uint8List storeKey,
  required Uint8List storeId,
}) async {
  final prefix = await _readPrefix(pin);
  final trailer = await _readExact(
    pin,
    offset: pin.length - v2ManifestLengthBytes,
    length: v2ManifestLengthBytes,
  );
  final manifestLength = decodeManifestLength(trailer);
  final layout = deriveStoreLayout(
    fileLength: pin.length,
    bootstrap: prefix.bootstrap,
    sealedManifestLength: manifestLength,
  );
  final sealedManifest = await _readExact(
    pin,
    offset: layout.manifestOffset,
    length: layout.manifestLength,
  );
  final domain = host.binding.domain.copyBytes();
  V2Manifest? manifest;
  try {
    manifest = await openManifest(
      storeKey: storeKey,
      storeId: storeId,
      storageDomain: domain,
      bootstrap: prefix.bootstrap,
      sealedPackage: prefix.sealedPackage,
      sealedManifest: sealedManifest,
    );
    final ranges = deriveFrameRanges(
      manifest,
      frameRegionLength: layout.frameRegionLength,
    );
    return _OpenedGeneration(
      prefix: prefix,
      layout: layout,
      manifest: manifest,
      ranges: ranges,
    );
  } catch (_) {
    manifest?.clear();
    rethrow;
  }
}

Future<void> _requireCompleteStore(StoreTransaction transaction) async {
  final artifacts = await transaction.observeArtifacts();
  if (artifacts.hasTransactionArtifacts) {
    throw _error(
      KeybayErrorCode.storeStateConflict,
      'The V2 store has incomplete transaction state.',
    );
  }
  if (!artifacts.hasLiveFile) {
    throw _error(
      KeybayErrorCode.storeStateConflict,
      'The V2 store is unavailable.',
    );
  }
}

Future<PinnedStoreFile> _openPin(
  Future<PinnedStoreFile?> Function() openPinnedLive,
) async {
  final pin = await openPinnedLive();
  if (pin == null) {
    throw _error(
      KeybayErrorCode.storeStateConflict,
      'The V2 store changed before it could be pinned.',
    );
  }
  final length = pin.length;
  if (length <
          v2BootstrapCoreFixedBytes +
              v2BootstrapLengthBytes +
              1 +
              V2StoreLimits.sealedFrameOverhead +
              4 +
              v2ManifestLengthBytes ||
      length > V2StoreLimits.storeBytes) {
    final failure = _error(
      KeybayErrorCode.limitExceeded,
      'The V2 store file is outside its published size bound.',
    );
    await _closePin(pin);
    throw failure;
  }
  return pin;
}

Future<_StorePrefix> _readPrefix(PinnedStoreFile pin) async {
  final fixed = await _readExact(
    pin,
    offset: 0,
    length: v2BootstrapCoreFixedBytes,
  );
  final coreLength = decodeBootstrapCoreLength(fixed);
  final bootstrapLength = coreLength + v2BootstrapLengthBytes;
  final bootstrapBytes = await _readExact(
    pin,
    offset: 0,
    length: bootstrapLength,
  );
  final bootstrap = decodeBootstrap(bootstrapBytes);
  final package = await _readExact(
    pin,
    offset: bootstrapLength,
    length: bootstrap.sealedPackageLength,
  );
  return _StorePrefix(bootstrap: bootstrap, sealedPackage: package);
}

Future<Uint8List> _readExact(
  PinnedStoreFile pin, {
  required int offset,
  required int length,
}) async {
  if (offset < 0 || length < 0 || offset > pin.length - length) {
    throw _error(
      KeybayErrorCode.storeAuthenticationFailed,
      'The V2 store contains an invalid component range.',
    );
  }
  final bytes = await pin.readExact(offset: offset, length: length);
  if (bytes.length != length) {
    throw _error(
      KeybayErrorCode.storageOperationFailed,
      'The V2 store could not be read exactly.',
    );
  }
  return bytes;
}

Future<KeybayException?> _closeOpenResources(
  PlatformRootLease? lease,
  PinnedStoreFile pin,
) async {
  KeybayException? first;
  if (lease != null) {
    try {
      await lease.close();
    } on Object catch (error) {
      first = _mapReaderFailure(error);
    }
  }
  final pinFailure = await _closePin(pin);
  return first ?? pinFailure;
}

Future<KeybayException?> _closePin(PinnedStoreFile pin) async {
  try {
    await pin.close();
    return null;
  } on Object catch (error) {
    return _mapReaderFailure(error);
  }
}

void _clearResults(
  Map<String, Uint8List?>? values, [
  V2StoreEngineTestProbe? testProbe,
]) {
  if (values == null) return;
  for (final value in values.values) {
    if (value != null) {
      _clear(value);
      testProbe?._recordDiscardedValue(value);
    }
  }
}

void _clearBuffers(List<Uint8List> buffers) {
  for (final buffer in buffers) {
    _clear(buffer);
  }
}

KeybayException _mapReaderFailure(Object error) {
  if (error is KeybayException) return error;
  if (error is ApplicationIdentityFailure) {
    return _error(
      KeybayErrorCode.applicationIdentityUnavailable,
      'The host application identity could not be established.',
    );
  }
  if (error is PlatformProtectorFailure) {
    final code = switch (error.code) {
      PlatformProtectorFailureCode.unavailable =>
        KeybayErrorCode.platformProtectorUnavailable,
      PlatformProtectorFailureCode.busy => KeybayErrorCode.storeBusy,
      PlatformProtectorFailureCode.locked =>
        KeybayErrorCode.platformProtectorLocked,
      PlatformProtectorFailureCode.interactionRequired =>
        KeybayErrorCode.platformInteractionRequired,
      PlatformProtectorFailureCode.invalidated =>
        KeybayErrorCode.platformKeyInvalidated,
      PlatformProtectorFailureCode.stateConflict =>
        KeybayErrorCode.storeStateConflict,
      PlatformProtectorFailureCode.authenticationFailed =>
        KeybayErrorCode.storeAuthenticationFailed,
      PlatformProtectorFailureCode.resetIncomplete =>
        KeybayErrorCode.resetIncomplete,
      PlatformProtectorFailureCode.operationFailed ||
      PlatformProtectorFailureCode.leaseClosed =>
        KeybayErrorCode.platformOperationFailed,
    };
    return _error(code, 'The platform protection operation failed.');
  }
  if (error is StoreFilesFailure) {
    final code = switch (error.code) {
      StoreFilesFailureCode.busy => KeybayErrorCode.storeBusy,
      StoreFilesFailureCode.resetIncomplete => KeybayErrorCode.resetIncomplete,
      StoreFilesFailureCode.operationFailed ||
      StoreFilesFailureCode.resetNotStarted ||
      StoreFilesFailureCode.pinnedFileClosed =>
        KeybayErrorCode.storageOperationFailed,
    };
    return _error(code, 'The identity-derived storage operation failed.');
  }
  if (error is V2EntropyFailure) {
    return _error(
      KeybayErrorCode.entropyUnavailable,
      'Secure entropy is unavailable.',
    );
  }
  if (error is V2PassphraseDerivationFailure) {
    final code = switch (error.code) {
      V2PassphraseDerivationFailureCode.invalidInput =>
        KeybayErrorCode.invalidAuthInput,
      V2PassphraseDerivationFailureCode.operationFailed =>
        KeybayErrorCode.storageOperationFailed,
    };
    return _error(code, 'The passphrase operation failed.');
  }
  if (error is V2FormatFailure) {
    final code = switch (error.code) {
      V2FormatFailureCode.unsupportedSuite ||
      V2FormatFailureCode.unsupportedPolicy ||
      V2FormatFailureCode.unsupportedKdfProfile =>
        KeybayErrorCode.unsupportedStoreVersion,
      V2FormatFailureCode.limitExceeded => KeybayErrorCode.limitExceeded,
      V2FormatFailureCode.invalidEncoding =>
        KeybayErrorCode.storeAuthenticationFailed,
    };
    return _error(code, 'The V2 store format is invalid.');
  }
  if (error is V2CryptoFailure) {
    return _error(
      KeybayErrorCode.storeAuthenticationFailed,
      'The V2 store failed cryptographic authentication.',
    );
  }
  return _error(
    KeybayErrorCode.storageOperationFailed,
    'The V2 store operation failed.',
  );
}

/// Whether a V2 session's retained key material has been erased.
///
/// This is internal deterministic test instrumentation, not package API.
bool debugStoreSessionKeyIsCleared(V2StoreSession session) =>
    session._storeKey.every((byte) => byte == 0) &&
    session._storeId.every((byte) => byte == 0);

/// Internal deterministic observations for secret cleanup tests.
///
/// Aggregate observations retain no buffers. The optional input observer lets
/// tests retain aliases to verify clearing after an operation settles. This
/// instrumentation is not exported by the package API.
final class V2StoreEngineTestProbe {
  V2StoreEngineTestProbe({this.onOperationInput});

  /// Observes an operation-owned input synchronously, without copying it.
  final void Function(Uint8List bytes)? onOperationInput;

  int _discardedValueCount = 0;
  bool _discardedValuesWereCleared = true;
  bool? _failedOpenKeyMaterialWasCleared;

  int get discardedValueCount => _discardedValueCount;

  bool get discardedValuesWereCleared => _discardedValuesWereCleared;

  bool? get failedOpenKeyMaterialWasCleared => _failedOpenKeyMaterialWasCleared;

  void _recordDiscardedValue(Uint8List value) {
    _discardedValueCount++;
    _discardedValuesWereCleared &= value.every((byte) => byte == 0);
  }

  void _recordFailedOpen(V2StoreSession session) {
    _failedOpenKeyMaterialWasCleared = debugStoreSessionKeyIsCleared(session);
  }
}
