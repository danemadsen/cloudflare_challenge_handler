import 'package:dio/dio.dart';

class CallbackInterceptor extends Interceptor {
  final String _key;
  final void Function(Response, ResponseInterceptorHandler) _onResponse;
  final void Function(DioException, ErrorInterceptorHandler) _onError;

  CallbackInterceptor({
    required String key,
    required void Function(Response, ResponseInterceptorHandler) onResponse,
    required void Function(DioException, ErrorInterceptorHandler) onError,
  }) : _key = key, _onResponse = onResponse, _onError = onError;

  String get key => _key;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) => _onResponse(response, handler);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) => _onError(err, handler);
}