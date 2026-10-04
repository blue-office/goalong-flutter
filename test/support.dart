import 'dart:async';
import 'dart:convert';

import 'package:goalong/goalong.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryStorage implements GoAlongStorage {
  final values = <String, Object>{};
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

typedef Responder = FutureOr<http.Response> Function(http.Request request);

class Harness {
  Harness({MemoryStorage? storage, bool reported = true})
      : storage = storage ?? MemoryStorage() {
    if (reported) this.storage.values['goalong.installation_reported'] = true;
    client = MockClient((request) async {
      requests.add(request);
      return responder(request);
    });
  }

  final MemoryStorage storage;
  final requests = <http.Request>[];
  late final MockClient client;
  Responder responder = defaultResponse;

  static http.Response defaultResponse(http.Request request) {
    if (request.url.path.endsWith('/installations')) {
      return jsonResponse({'ok': true});
    }
    if (request.url.path.endsWith('/current')) {
      return jsonResponse({'status': 'none'});
    }
    if (request.url.path.endsWith('/config')) {
      return jsonResponse({'entryEnabled': true, 'cacheMaxAgeSeconds': 60});
    }
    if (request.url.path.endsWith('/validate')) {
      return jsonResponse({
        'valid': true,
        'creator': {'displayName': 'MIKA'},
      });
    }
    return jsonResponse({
      'status': 'applied',
      'creator': {'displayName': 'MIKA'},
    });
  }

  Future<void> configure({
    ActiveSubscriberCheck? isActiveSubscriber,
    String baseUrl = 'https://goalong.me',
    String? appSlug = 'booknotion',
  }) =>
      GoAlong.configure(
        appId: 'test-app',
        appSlug: appSlug,
        baseUrl: baseUrl,
        storage: storage,
        httpClient: client,
        appVersion: '1.2.3',
        osVersion: 'testOS',
        locale: 'ja-JP',
        isActiveSubscriber: isActiveSubscriber,
      );

  List<http.Request> calls(String endpoint) => requests
      .where((request) => request.url.path == '/api/sdk/v1/$endpoint')
      .toList();

  Map<String, dynamic> body(String endpoint) =>
      jsonDecode(calls(endpoint).last.body) as Map<String, dynamic>;
}
