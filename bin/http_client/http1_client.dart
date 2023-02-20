import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';

import 'http_base.dart';
import 'package:http/io_client.dart' as io_client;

class Http1Client extends HttpBase {
  final HttpClient _client = HttpClient();

  @override
  Future<StreamedResponse> send(BaseRequest request,
      {Completer<Stream<double>>? uploadStreamCompleter}) async {
    final stream = request.finalize();
    final StreamController<double> sc = StreamController<double>();

    try {
      final contentLength = request.contentLength ?? -1;
      final ioRequest = (await _client.openUrl(request.method, request.url))
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..contentLength = contentLength
        ..persistentConnection = request.persistentConnection;

      request.headers.forEach((name, value) {
        ioRequest.headers.set(name, value);
      });

      int uploadedDataCount = 0;
      uploadStreamCompleter?.complete(sc.stream);
      final processCompleter = Completer();
      final requestCompleter = Completer();
      final sl = stream.listen(
        (value) {
          ioRequest.add(value);
          uploadedDataCount += value.length;
          final percentage = uploadedDataCount / contentLength;
          sc.add(
            percentage.isNaN ? 99 : percentage,
          );
        },
        onError: (e, st) {
          ioRequest.addError(e, st);
          sc.addError(e, st);
        },
        onDone: () {
          ioRequest.close().then((value) {
            sc
              ..add(1)
              ..close();
            processCompleter.complete();
            requestCompleter.complete(value);
            return;
          }).catchError((e, st) {
            sc
              ..addError(e, st)
              ..close();
            return;
          });
        },
      );
      await processCompleter.future;
      await sl.cancel();

      final HttpClientResponse response = await requestCompleter.future;

      final headers = <String, String>{};
      response.headers.forEach((key, values) {
        headers[key] = values.join(',');
      });

      return io_client.IOStreamedResponse(
        response.handleError(
          (error) {
            final httpException = error as HttpException;
            throw ClientException(httpException.message, httpException.uri);
          },
          test: (error) => error is HttpException,
        ),
        response.statusCode,
        contentLength:
            response.contentLength == -1 ? null : response.contentLength,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        inner: response,
      );
    } on HttpException catch (error) {
      throw ClientException(error.message, error.uri);
    } finally {
      if (!sc.isClosed) {
        unawaited(sc.close());
      }
    }
  }
}
