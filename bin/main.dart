import 'package:http/http.dart';

import 'http_client/http1_client.dart';
import 'http_client/http2_client.dart';
import 'http_client/http_base.dart';

HttpBase? _client1;
HttpBase? _client2;

Future<void> main(List<String> arguments) async {
  //create [count] requests without waiting each response
  final totalRequest = 50;
  final timeH1 = await executeHttp1(count: totalRequest);
  final timeH2 = await executeHttp2(count: totalRequest);
  print('Time H1: $timeH1 ms\nTime H2: $timeH2 ms');
  print('Different in percentage: ${(timeH1 - timeH2) / timeH1 * 100}%');
}

Future<int> executeHttp1({required int count}) async {
  Future<Response> execute() async {
    _client1 ??= Http1Client();
    return await _client1!.get(Uri.parse(
      'https://api.smallog.tech/card-manager/v2/cards/f2dcf489-0d5b-4da9-96fc-cb39ecc9b5b1',
    ));
  }

  return watch(action: execute, count: count, note: 'HTTP/1');
}

Future<int> executeHttp2({required int count}) async {
  Future<Response> execute() async {
    _client2 ??= Http2Client(Uri.parse('https://api.smallog.tech'));
    return _client2!.get(Uri.parse(
      '/card-manager/v2/cards/f2dcf489-0d5b-4da9-96fc-cb39ecc9b5b1',
    ));
  }

  return watch(action: execute, count: count, note: 'HTTP/2');
}

Future<int> watch({
  required Future<Response> Function() action,
  required int count,
  required String note,
}) async {
  try {
    final startTime = DateTime.now();

    final List<Future<Response>> reqCount = [];

    for (var i = 1; i <= count; i++) {
      final response = action();
      reqCount.add(response);
    }
    print('[$note] $count requests has been executed\nProcessing...');

    await Future.wait(reqCount);

    final endTime = DateTime.now();

    return endTime.difference(startTime).inMilliseconds;
  } catch (e, st) {
    print('Error happens: ${e.toString()} ${st.toString()}');
    rethrow;
  }
}
