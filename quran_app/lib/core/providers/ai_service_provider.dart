/// Riverpod providers wrapping the AI microservice HTTP client.
///
/// These providers are the single integration point between Flutter UI code
/// and the local FastAPI AI backend. Any screen that needs semantic search,
/// recitation evaluation, or vision detection reads from these providers.
library ai_service_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_service_client.dart';

// ── Base URL ──────────────────────────────────────────────────────────────────

/// The base URL of the local AI microservice.
///
/// On Android emulator: 10.0.2.2 reaches the host machine.
/// On a physical device: set to the host machine's LAN IP.
/// On iOS simulator: 127.0.0.1 works directly.
///
/// TODO: expose this in Settings so the user can point to a remote server.
const String _kDefaultAiBaseUrl = 'http://127.0.0.1:8765';

final aiBaseUrlProvider = Provider<String>(
  (ref) => _kDefaultAiBaseUrl,
  name: 'aiBaseUrlProvider',
);

// ── Client ────────────────────────────────────────────────────────────────────

/// The singleton [AIServiceClient] for the app lifetime.
final aiServiceClientProvider = Provider<AIServiceClient>(
  (ref) {
    final baseUrl = ref.watch(aiBaseUrlProvider);
    return AIServiceClient(baseUrl: baseUrl);
  },
  name: 'aiServiceClientProvider',
);

// ── Health polling ────────────────────────────────────────────────────────────

/// Streams the AI service reachability state, re-checked every 30 s.
///
/// UI widgets can watch this to show "AI Offline / Online" badges.
final aiServiceHealthProvider = StreamProvider<bool>(
  (ref) async* {
    final client = ref.watch(aiServiceClientProvider);
    while (true) {
      yield await client.checkHealth();
      await Future<void>.delayed(const Duration(seconds: 30));
    }
  },
  name: 'aiServiceHealthProvider',
);

// ── Semantic search ───────────────────────────────────────────────────────────

/// The current semantic search query string (drives [semanticSearchProvider]).
final semanticSearchQueryProvider = StateProvider<String>(
  (ref) => '',
  name: 'semanticSearchQueryProvider',
);

/// Fires a semantic RAG search whenever [semanticSearchQueryProvider] changes.
///
/// Returns null for an empty query so the UI can show a "hints" placeholder.
final semanticSearchProvider = FutureProvider.autoDispose
    .family<AiSearchResponse?, String>(
  (ref, query) async {
    if (query.trim().isEmpty) return null;
    final client = ref.watch(aiServiceClientProvider);
    return client.semanticSearch(
      query.trim(),
      topK: 7,
      includeTafseer: true,
    );
  },
  name: 'semanticSearchProvider',
);
