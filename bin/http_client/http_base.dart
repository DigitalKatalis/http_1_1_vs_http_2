import 'dart:async';

import 'package:http/http.dart';

abstract class HttpBase extends BaseClient {
  @override
  Future<StreamedResponse> send(
    BaseRequest request, {
    Completer<Stream<double>>? uploadStreamCompleter,
  });
}
