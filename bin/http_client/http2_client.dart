import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'dart:convert';

import 'package:http/http.dart';
import 'package:http2/http2.dart';

import 'http_base.dart';

class Http2Client implements HttpBase {
  Http2Client(Uri host) : _host = host {
    _connection.complete(init());
  }

  final Uri _host;

  final Completer<ClientTransportConnection> _connection = Completer();

  @override
  void close() {
    _connection.future.then((value) => value.terminate());
  }

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('HEAD', url, headers);

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('GET', url, headers);

  @override
  Future<Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('POST', url, headers, body, encoding);

  @override
  Future<Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('PUT', url, headers, body, encoding);

  @override
  Future<Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('PATCH', url, headers, body, encoding);

  @override
  Future<Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('DELETE', url, headers, body, encoding);

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.bodyBytes;
  }

  /// Throws an error if [response] is not successful.
  void _checkResponseSuccess(Uri url, Response response) {
    if (response.statusCode < 400) return;
    String message =
        'Request to $url failed with status ${response.statusCode}';
    if (response.reasonPhrase != null) {
      message = '$message: ${response.reasonPhrase}';
    }
    throw ClientException('$message.', url);
  }

  Future<Response> _sendUnstreamed(
    String method,
    Uri url,
    Map<String, String>? headers, [
    Object? body,
    Encoding? encoding,
  ]) async {
    final request = Request(method, url);

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      } else {
        throw ArgumentError('Invalid request body "$body".');
      }
    }

    return Response.fromStream(await send(request));
  }

  @override
  Future<StreamedResponse> send(
    BaseRequest request, {
    Completer<Stream<double>>? uploadStreamCompleter,
  }) async {
    String requestUrlOrHost(String Function(Uri) fn) =>
        fn(request.url).isEmpty ? fn(_host) : fn(request.url);
    final reqStream = request.finalize();
    final headers = <String, String>{
      ':method': request.method,
      ':path': request.url.path,
      ':scheme': requestUrlOrHost((url) => url.scheme),
      ':authority': requestUrlOrHost((url) => url.authority),
      ...request.headers,
      'traceparent': '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
      'content-length': request.contentLength.toString(),
    };

    final h2Headers = headers.entries
        .map((h) => Header.ascii(h.key.toLowerCase(), h.value))
        .toList();

    final connection = await _connection.future;
    final h2Request = connection.makeRequest(h2Headers);

    final requestStream = reqStream.listen(
      (bytes) {
        h2Request.sendData(bytes);
      },
      onDone: () {
        h2Request.outgoingMessages.close();
      },
      onError: (_, __) {
        h2Request.outgoingMessages.close();
      },
      cancelOnError: true,
    );

    await h2Request.outgoingMessages.done;
    await requestStream.cancel();

    final responseHeader = <String, String>{};

    final incomings = await h2Request.incomingMessages.toList();
    final responseData = <List<int>>[];
    for (final message in incomings) {
      if (message is HeadersStreamMessage) {
        for (final header in message.headers) {
          final name = utf8.decode(header.name);
          final value = utf8.decode(header.value);
          responseHeader[name] = value;
        }
      } else if (message is DataStreamMessage) {
        responseData.add(message.bytes);
      }
      if (message.endStream) {}
    }

    return StreamedResponse(
      // responseBodyStream,
      Stream.fromIterable(responseData),
      int.parse(responseHeader[':status']!),
      request: request,
      headers: responseHeader,
    );
  }

  Future<ClientTransportConnection> init() async {
    try {
      final socket = await SecureSocket.connect(
        _host.host,
        _host.port,
        onBadCertificate: (_) => true,
        supportedProtocols: ['http/1.1', 'http/1.2', 'h2'],
      );
      return ClientTransportConnection.viaSocket(socket);
    } catch (e) {
      print('Something happens when creating transport, ${e.toString()}');
      rethrow;
    }
  }
}
