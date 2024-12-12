import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart';

extension ResponseExtension on Response {
  Future<bool> get isCloudflareChallenge async {
    if (
      (statusCode == 403 || statusCode == 503) &&
      (headers.value('content-type')?.contains('text/html') ?? false)
    ) {
      final html = await _responseBodyAsString(data);
      final document = parse(html);
      final title = document.querySelector('title')?.text.toLowerCase() ?? '';
      return title.contains('cloudflare') ||
             title.contains('just a moment') ||
             title.contains('verification required');
    }
    return false;
  }

  Future<String> _responseBodyAsString(dynamic data) async {
    if (data is String) return data;
    if (data is List<int>) return utf8.decode(data);
    if (data is ResponseBody) return utf8.decodeStream(data.stream);
    return jsonEncode(data);
  }
}