import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supertokens_flutter/src/anti-csrf.dart';
import 'package:supertokens_flutter/src/dio-interceptor-wrapper.dart';
import 'package:supertokens_flutter/src/front-token.dart';
import 'package:supertokens_flutter/src/supertokens.dart';
import 'package:supertokens_flutter/supertokens.dart';

import 'test-utils.dart';

void main() {
  String apiBasePath = SuperTokensTestUtils.baseUrl;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    return SuperTokensTestUtils.beforeAllTest();
  });
  setUp(() async {
    // TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    SuperTokensTestUtils.beforeEachTest();
    SuperTokens.isInitCalled = false;
    await AntiCSRF.removeToken();
    await FrontToken.removeToken();
    return Future.delayed(Duration(seconds: 1));
  });
  tearDownAll(() => SuperTokensTestUtils.afterAllTest());

  Dio setUpDio({String? url}) {
    Dio dio = Dio(
      BaseOptions(
        baseUrl: apiBasePath,
        connectTimeout: 5000,
        receiveTimeout: 500,
      ),
    );
    dio.interceptors.add(SuperTokensInterceptorWrapper(client: dio));
    return dio;
  }

  test("Test session expired without refresh call", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    SuperTokens.init(apiDomain: apiBasePath);
    Dio dio = setUpDio();
    var resp = await dio.get("/");
    if (resp.statusCode != 401)
      fail("API should have returned unAuthorised but didn't");
    int counter = await SuperTokensTestUtils.refreshTokenCounter();
    if (counter != 0) fail("Refresh counter returned non zero value");
  });

  test("Test custom headers for refresh API", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    SuperTokens.init(
      apiDomain: apiBasePath,
      preAPIHook: (action, req) {
        if (action == APIAction.REFRESH_TOKEN)
          req.headers.addAll({"custom-header": "custom-value"});
        return req;
      },
    );
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200)
      fail("Login req failed");
    else {
      await Future.delayed(Duration(seconds: 10), () {});
      var userInfoResp = await dio.get("/");
      if (userInfoResp.statusCode != 200) {}
    }
    var refreshResponse = await dio.get("/refreshHeader");
    if (refreshResponse.statusCode != 200) fail("Refresh Request failed");
    var respJson = refreshResponse.data;
    if (respJson["value"] != "custom-value") fail("Header not sent");
  });

  test("Test to check if request can be made without Supertokens.init",
      () async {
    await SuperTokensTestUtils.startST(validity: 3);
    dynamic error;
    try {
      RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
      Dio dio = setUpDio();
      await dio.fetch(req);
      fail("Request should have failed but didnt");
    } on DioError catch (e) {
      error = e.error;
    }

    assert(error != null);
    assert(error.toString() ==
        "SuperTokens.initialise must be called before using Client");
  });

  test('More than one calls to init works', () async {
    await SuperTokensTestUtils.startST(validity: 5);
    try {
      SuperTokens.init(apiDomain: apiBasePath);
      SuperTokens.init(apiDomain: apiBasePath);
    } catch (e) {
      fail("Calling init more than once fails the test");
    }
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");
    try {
      SuperTokens.init(apiDomain: apiBasePath);
    } catch (e) {
      fail("Calling init more than once fails the test");
    }
    var userInfoResp = await dio.get("/");
    if (userInfoResp.statusCode != 200)
      fail("UserInfo API returned ${userInfoResp.statusCode} ");
  });

  test("Test if refresh is called after access token expires", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    bool failed = false;
    SuperTokens.init(apiDomain: apiBasePath);
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");
    await Future.delayed(Duration(seconds: 5), () {});
    var userInfoResp = await dio.get("/");
    if (userInfoResp.statusCode != 200) failed = true;

    int counter = await SuperTokensTestUtils.refreshTokenCounter();
    if (counter != 1) failed = true;

    assert(!failed);
  });

  // test('Refresh only get called once after multiple request (Concurrency)',
  //     () async {
  //   bool failed = false;
  //   await SuperTokensTestUtils.startST(validity: 10);
  //   List<bool> results = [];
  //   SuperTokens.init(apiDomain: apiBasePath);
  //   RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
  //   Dio dio = setUpDio();
  //   var resp = await dio.fetch(req);
  //   if (resp.statusCode != 200) fail("Login req failed");
  //   List<Future> reqs = [];
  //   for (int i = 0; i < 300; i++) {
  //     dio.get("").then((resp) {
  //       if (resp.statusCode == 200)
  //         results.add(true);
  //       else
  //         results.add(false);
  //     });
  //   }
  //   await Future.wait(reqs);
  //   int refreshCount = await SuperTokensTestUtils.refreshTokenCounter();
  //   if (refreshCount != 1 && !results.contains(false) && results.length == 300)
  //     fail("");
  // });

  test("Test does session exist after user is loggedIn", () async {
    await SuperTokensTestUtils.startST(validity: 1);
    bool sessionExist = false;
    SuperTokens.init(apiDomain: apiBasePath);
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");
    sessionExist = await SuperTokens.doesSessionExist();
    // logout
    var logoutResp = await dio.post("/logout");
    if (logoutResp.statusCode != 200) fail("Logout req failed");
    sessionExist = await SuperTokens.doesSessionExist();
    assert(!sessionExist);
  });

  test("Test if not logged in  the  Auth API throws session expired", () async {
    await SuperTokensTestUtils.startST(validity: 1);
    SuperTokens.init(apiDomain: apiBasePath);
    Dio dio = setUpDio();
    var resp = await dio.get("/");

    if (resp.statusCode != 401) {
      fail("API should have returned session expired (401) but didnt");
    }
  });

  test("Test other other domains work without Authentication", () async {
    await SuperTokensTestUtils.startST(validity: 1);
    SuperTokens.init(apiDomain: apiBasePath);
    String url = 'http://www.google.com/';
    Dio dio = setUpDio(url: url);
    var respGoogle1 = await dio.get('');
    if (respGoogle1.statusCode! > 300) fail("external API did not work");
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio2 = setUpDio();
    var loginResp = await dio2.fetch(req);
    if (loginResp.statusCode != 200) fail("Login req failed");
    var respGoogle2 = await dio.get('');
    if (respGoogle2.statusCode! > 300) fail("external API did not work");
    // logout
    var logoutResp = await dio2.post("/logout");
    if (logoutResp.statusCode != 200) fail("Logout req failed");
    var respGoogle3 = await dio.get('');
    if (respGoogle3.statusCode! > 300) fail("external API did not work");
  });
}
