import 'dart:async';
import 'dart:io' as io;

import 'package:cloudflare_interceptor/src/request_options_extension.dart';
import 'package:cloudflare_interceptor/src/response_extension.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart';

class CloudflareInterceptor extends Interceptor {
  final Dio dio;
  final CookieJar cookieJar;
  final BuildContext Function() getBuildContext;

  Completer<String?> _completer = Completer<String?>.sync();
  bool _usingDialog = false;

  CloudflareInterceptor({
    required this.dio, 
    required this.cookieJar, 
    required this.getBuildContext
  });

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (await response.isCloudflareChallenge) {
      // Solve challenge using a WebView
      try {
        solveCloudflare(response.requestOptions);
        final solvedData = await _completer.future;
        if (solvedData != null) {
          final newResponse = Response(
            requestOptions: response.requestOptions,
            data: solvedData,
            statusCode: 200,
            extra: {'cloudflare': true},
          );
          handler.next(newResponse);
        }
      } catch (e) {
        handler.reject(DioException(requestOptions: response.requestOptions, error: e));
      }
    }
    else {
      // If not a Cloudflare challenge, proceed as normal
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response != null && await err.response!.isCloudflareChallenge) {
      try {
        solveCloudflare(err.requestOptions);
        final solvedData = await _completer.future;
        if (solvedData != null) {
          final newResponse = Response(
            requestOptions: err.requestOptions,
            data: solvedData,
            statusCode: 200,
            extra: {'cloudflare': true},
          );
          handler.resolve(newResponse);
        }
      } catch (e) {
        handler.reject(DioException(requestOptions: err.requestOptions, error: e));
      }
    }
    else {
      // If not a Cloudflare challenge, proceed as normal
      handler.next(err);
    }
  }

  void solveCloudflare(RequestOptions requestOptions) async {
    _completer = Completer();

    final initialSettings = requestOptions.getWebViewSettings();

    final initialUrlRequest = await requestOptions.getURLRequest();

    final headlessWebView = HeadlessInAppWebView(
			initialSettings: initialSettings,
			initialUrlRequest: initialUrlRequest,
			onLoadStop: onLoadStop,
		);

    await headlessWebView.run();

    await Future.any([
			_completer.future,
			Future.delayed(const Duration(seconds: 5))
		]);

    if (_completer.isCompleted) {
      headlessWebView.dispose();
      return;
    }
    
    final context = getBuildContext();

    if (!context.mounted) throw Exception('Context is not mounted');

    showDialog(
      context: context, 
      builder: (context) => Dialog.fullscreen(
        child: InAppWebView(
		  		headlessWebView: headlessWebView,
		  		initialSettings: initialSettings,
		  		initialUrlRequest: initialUrlRequest,
		  		onLoadStop: onLoadStop,
		  	)
      )
    );

    _usingDialog = true;
  }

  void onLoadStop(InAppWebViewController controller, WebUri? uri) async {
    final html = await controller.getHtml();
    if (html == null) return;

    final doc = parse(html);
    final title = doc.querySelector('title')?.text.toLowerCase() ?? '';

    // If the title no longer matches challenge keywords, we consider it solved.
    if (
      title.contains('cloudflare') ||
      title.contains('just a moment') ||
      title.contains('verification required')
    ) return;
    
    // Get cookies from the WebView (InAppWebViewCookie)
    final inAppCookies = await CookieManager.instance().getCookies(url: uri!);

    // Convert InAppWebViewCookie to dart:io Cookie
    final ioCookies = inAppCookies.map((c) {
      final cookie = io.Cookie(c.name, c.value);
      cookie.domain = c.domain;
      cookie.path = c.path ?? '/';
      if (c.expiresDate != null) {
        cookie.expires = DateTime.fromMillisecondsSinceEpoch(c.expiresDate!);
      }
      cookie.secure = c.isSecure ?? false;
      cookie.httpOnly = c.isHttpOnly ?? false;
      return cookie;
    }).toList();

    // Store the converted cookies in the Dio cookie jar
    cookieJar.saveFromResponse(uri, ioCookies);

    // Complete the challenge
    _completer.complete(html);

    // Dismiss the dialog
    if (_usingDialog) {
      final context = getBuildContext();

      if (!context.mounted) throw Exception('Context is not mounted');
      
      Navigator.of(context).pop();

      _usingDialog = false;
    }
  }
}