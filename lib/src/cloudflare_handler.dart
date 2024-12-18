import 'dart:async';
import 'dart:io' as io;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie_manager;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart';

import 'callback_interceptor.dart';
import 'request_options_extension.dart';
import 'response_extension.dart';

class CloudflareChallengeHandler extends StatefulWidget {
  final Dio dio;
  final CookieJar cookieJar;

  CloudflareChallengeHandler({
    super.key, 
    required this.dio,
    CookieJar? cookieJar
  }) : cookieJar = cookieJar ?? CookieJar() {
    if (cookieJar == null) {
      dio.interceptors.add(dio_cookie_manager.CookieManager(this.cookieJar));
    }
  }

  @override
  State<CloudflareChallengeHandler> createState() => _CloudflareChallengeHandlerState();
}

class _CloudflareChallengeHandlerState extends State<CloudflareChallengeHandler> {
  bool isChallanging = false;
  bool needsUserInput = false;
  InAppWebViewSettings? initialSettings;
  URLRequest? initialUrlRequest;
  Completer<String?> completer = Completer<String?>.sync();
  HeadlessInAppWebView? headlessWebView;

  void cleanup() {
    isChallanging = false;
    needsUserInput = false;
    initialSettings = null;
    initialUrlRequest = null;
    headlessWebView = null;
    setState(() {});
  }

  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (await response.isCloudflareChallenge) {
      setState(() => isChallanging = true);

      // Solve challenge using a WebView
      try {
        solveCloudflare(response.requestOptions);
        final solvedData = await completer.future;
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

    cleanup();
  }

  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response != null && await err.response!.isCloudflareChallenge) {
      setState(() => isChallanging = true);

      try {
        solveCloudflare(err.requestOptions);
        final solvedData = await completer.future;
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

    cleanup();
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
    widget.cookieJar.saveFromResponse(uri, ioCookies);

    // Complete the challenge
    completer.complete(html);
  }

  void solveCloudflare(RequestOptions requestOptions) async {
    completer = Completer();

    initialSettings = requestOptions.getWebViewSettings();

    initialUrlRequest = await requestOptions.getURLRequest();

    headlessWebView = HeadlessInAppWebView(
			initialSettings: initialSettings,
			initialUrlRequest: initialUrlRequest,
			onLoadStop: onLoadStop,
		);

    await headlessWebView!.run();

    await Future.any([
			completer.future,
			Future.delayed(const Duration(seconds: 5))
		]);

    if (completer.isCompleted) {
      headlessWebView?.dispose();
    }
    else {
      needsUserInput = true;
    }

    setState(() {});
  }

  @override
  void initState() {
    widget.dio.interceptors.add(CallbackInterceptor(
      key: 'cloudflare',
      onResponse: onResponse,
      onError: onError,
    ));
    super.initState();
  }

  @override
  void dispose() {
    widget.dio.interceptors.removeWhere((i) => i is CallbackInterceptor && i.key == 'cloudflare');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isChallanging) {
      if (
        needsUserInput && 
        headlessWebView != null && 
        initialSettings != null && 
        initialUrlRequest != null
      ) {
        return SafeArea(
					child: InAppWebView(
						headlessWebView: headlessWebView,
						initialSettings: initialSettings,
						initialUrlRequest: initialUrlRequest,
						onLoadStop: onLoadStop,
					)
				);
      }

      return const Center(child: CircularProgressIndicator());
    }

    return const SizedBox.shrink();
  }
}