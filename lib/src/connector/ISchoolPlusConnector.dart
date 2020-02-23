import 'dart:convert';
import 'dart:io';
import 'package:big5/big5.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_app/debug/log/Log.dart';
import 'package:flutter_app/src/connector/core/Connector.dart';
import 'package:flutter_app/src/connector/core/RequestsConnector.dart';
import 'package:flutter_app/src/store/json/CourseFileJson.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:tripledes/tripledes.dart';
import 'core/ConnectorParameter.dart';

enum ISchoolPlusConnectorStatus {
  LoginSuccess,
  LoginFail,
  ConnectTimeOutError,
  NetworkError,
  UnknownError
}

class ISchoolPlusConnector {
  static bool _isLogin = true;

  static final String _iSchoolPlusUrl = "https://istudy.ntut.edu.tw/";
  static final String _getLoginISchoolUrl = _iSchoolPlusUrl + "mooc/login.php";
  static final String _postLoginISchoolUrl = _iSchoolPlusUrl + "login.php";
  static final String _iSchoolPlusIndexUrl = _iSchoolPlusUrl + "mooc/index.php";
  static final String _iSchoolPlusLearnIndexUrl =
      _iSchoolPlusUrl + "learn/index.php";
  static final String _checkLoginUrl = _iSchoolPlusLearnIndexUrl;
  static final String _getCourseName =
      _iSchoolPlusUrl + "learn/mooc_sysbar.php";

  static Future<ISchoolPlusConnectorStatus> login(
      String account, String password) async {
    String result;
    try {
      ConnectorParameter parameter;
      html.Document tagNode;
      List<html.Element> nodes;
      html.Element node;

      await RequestsConnector.deleteCookies(_iSchoolPlusUrl); //刪除先前登入

      parameter = ConnectorParameter(_getLoginISchoolUrl);
      result = await RequestsConnector.getDataByGet(parameter);

      tagNode = html.parse(result);
      node = tagNode.getElementById("loginForm");
      nodes = node.getElementsByTagName("input");
      String loginKey;
      for (html.Element node in nodes) {
        if (node.attributes["name"] == "login_key")
          loginKey = node.attributes['value'];
      }

      var bytes = utf8.encode(password);
      String md5Key = md5.convert(bytes).toString();
      String cypKey = md5Key.substring(0, 4) + loginKey.substring(0, 4);
      var blockCipher = new BlockCipher(new DESEngine(), cypKey);
      var encryptPwd = blockCipher.encodeB64(password);
      var password1 = base64.encode(utf8.encode(password));

      String passwordMask = "**********************************";
      Map<String, String> data = {
        "reurl": "",
        "login_key": loginKey,
        "encrypt_pwd": encryptPwd,
        "username": account,
        "password": passwordMask.substring(0, password.length),
        "password1": password1,
      };

      parameter = ConnectorParameter(_postLoginISchoolUrl);
      parameter.data = data;

      await RequestsConnector.getDataByPost(parameter);

      parameter = ConnectorParameter(_iSchoolPlusLearnIndexUrl);

      result = await RequestsConnector.getDataByGet(parameter);

      if (result.contains("Guest")) {
        //代表登入失敗
        return ISchoolPlusConnectorStatus.LoginFail;
      }
      _isLogin = true;
      return ISchoolPlusConnectorStatus.LoginSuccess;
    } catch (e) {
      Log.e(e.toString());
      return ISchoolPlusConnectorStatus.LoginFail;
    }
  }

  static Future<List<CourseFileJson>> getCourseFile(String courseId) async {
    ConnectorParameter parameter;
    String result;
    html.Document tagNode;
    html.Element node;
    RegExp exp;
    RegExpMatch matches;
    List<html.Element> resourceNodes, nodes, itemNodes;
    try {
      List<CourseFileJson> courseFileList = List();
      await _selectCourse(courseId);

      parameter = ConnectorParameter(_iSchoolPlusUrl + "learn/path/launch.php");
      result = await RequestsConnector.getDataByGet(parameter);
      exp = new RegExp(r"cid=(?<cid>\w+,)");
      matches = exp.firstMatch(result);
      String cid = matches.group(1);
      parameter =
          ConnectorParameter(_iSchoolPlusUrl + "learn/path/pathtree.php");
      parameter.data = {'cid': cid};

      result = await RequestsConnector.getDataByGet(parameter);
      tagNode = html.parse(result);
      node = tagNode.getElementById("fetchResourceForm");
      nodes = node.getElementsByTagName("input");

      Map<String, String> downloadPost = {
        'is_player': '',
        'href': '',
        'prev_href': '',
        'prev_node_id': '',
        'prev_node_title': '',
        'is_download': '',
        'begin_time': '',
        'course_id': '',
        'read_key': ''
      };

      for (html.Element node in nodes) {
        //將資料團入上方Map
        String key = node.attributes['name'];
        if (downloadPost.containsKey(key)) {
          downloadPost[key] = node.attributes['value'];
        }
      }

      parameter = ConnectorParameter(
          _iSchoolPlusUrl + "learn/path/SCORM_loadCA.php"); //取得下載檔案XML
      result = await RequestsConnector.getDataByGet(parameter);
/*
      xml.XmlDocument xmlDocument = xml.parse(result);
      Iterable<xml.XmlElement> itemIterable = xmlDocument.findAllElements("item");
      Iterable<xml.XmlElement> resourceIterable = xmlDocument.findAllElements("resource");
      Log.d( 'a' + itemIterable.toList()[0].text.split("\t")[0].replaceAll(RegExp("[\s|\n| ]"), "") );
 */
      tagNode = html.parse(result);
      itemNodes = tagNode.getElementsByTagName("item");
      resourceNodes = tagNode.getElementsByTagName("resource");

      for (int i = 0; i < itemNodes.length; i++) {
        String base = resourceNodes[i].attributes["xml:base"];
        String href = ((base != null) ? base : '') +
            '@' +
            resourceNodes[i].attributes["href"];

        CourseFileJson courseFile = CourseFileJson();
        courseFile.name = itemNodes[i].text.split("\t")[0].replaceAll(RegExp("[\s|\n| ]"), "");
        FileType fileType = FileType();
        downloadPost['href'] = href;
        fileType.href = await _getRealFileUrl(downloadPost);
        if ( fileType.href.toLowerCase().contains(".pdf")){
          fileType.type = CourseFileType.PDF;
        }
        courseFile.fileType = [fileType];
        courseFileList.add( courseFile );
    }

      return courseFileList;
    } catch (e) {
      Log.e(e.toString());
      return null;
    }
  }

  static Future<String> _getRealFileUrl(
      Map<String, String> postParameter) async {
    ConnectorParameter parameter;
    String url;
    try {
      parameter = ConnectorParameter(
          _iSchoolPlusUrl + "learn/path/SCORM_fetchResource.php");
      parameter.data = postParameter;
      http.Response response;
      await RequestsConnector.getDataByPostResponse(parameter).then((value) {
        response = value.rawResponse;
      });
      String result = big5.decode(response.bodyBytes); //使用bi5編碼

      if (response.statusCode == HttpStatus.ok) {
        RegExp exp = new RegExp("\"(?<url>/.+)\""); //找出開頭為 /  的 url
        RegExpMatch matches = exp.firstMatch(result);
        bool pass = (matches == null)
            ? false
            : (matches.groupCount == null) ? false : true;
        if (pass) {
          return _iSchoolPlusUrl + matches.group(1);
        } else {
          //是PDF預覽網址
          exp = new RegExp("\"(?<url>.+)\"");
          matches = exp.firstMatch(result);
          if (matches.group(1).toLowerCase().contains("http")) {
            //已經是網址
            return matches.group(1);
          }
          url = _iSchoolPlusUrl + "/learn/path/" + matches.group(1);
          parameter = ConnectorParameter(url); //去PDF預覽頁面取得真實下載網址
          result = await RequestsConnector.getDataByGet(parameter);
          exp = new RegExp("DEFAULT_URL.+'(?<url>.+)'");
          matches = exp.firstMatch(result);
          return _iSchoolPlusUrl + "/learn/path/" + matches.group(1);
        }
      } else if (response.isRedirect || result.isEmpty ) {
        //發生跳轉 出現檔案下載頁面
        url = response.headers[HttpHeaders.locationHeader];
        url = _iSchoolPlusUrl + "/learn/path/" + url;
        url = url.replaceAll("download_preview", "download"); //下載預覽頁面換成真實下載網址
        return url;
      }
    } catch (e) {
      //如果真實網址解析錯誤
      Log.e(e.toString());
      return null;
    }
    return null;
  }

  static Future<void> _selectCourse(String courseId) async {
    ConnectorParameter parameter;
    html.Document tagNode;
    html.Element node;
    List<html.Element> nodes;
    String result;
    try {
      parameter = ConnectorParameter(_getCourseName);
      result = await RequestsConnector.getDataByGet(parameter);

      tagNode = html.parse(result);
      node = tagNode.getElementById("selcourse");
      nodes = node.getElementsByTagName("option");
      String courseValue;
      for (int i = 1; i < nodes.length; i++) {
        node = nodes[i];
        String name = node.text.split("_").last;
        if (name == courseId) {
          courseValue = node.attributes["value"];
          break;
        }
      }
      String xml =
          "<manifest><ticket/><course_id>$courseValue</course_id><env/></manifest>";
      parameter = ConnectorParameter(
          "https://istudy.ntut.edu.tw/learn/goto_course.php");
      parameter.data = xml;
      await Connector.getDataByPost(
          parameter); //因為RequestsConnector無法傳送XML但是 DioConnector無法解析 Content-Type: text/html;;charset=UTF-8

    } catch (e) {
      throw e;
    }
  }

  static bool get isLogin {
    return _isLogin;
  }

  static void loginFalse() {
    _isLogin = false;
  }

  static Future<bool> checkLogin() async {
    Log.d("ISchoolPlus CheckLogin");
    ConnectorParameter parameter;
    _isLogin = false;
    try {
      parameter = ConnectorParameter(_checkLoginUrl);
      String result = await RequestsConnector.getDataByGet(parameter);
      if (result.contains("Guest")) {
        //代表登入失敗
        return false;
      } else {
        Log.d("ISchoolPlus Is Readly Login");
        _isLogin = true;
        return true;
      }
    } catch (e) {
      //throw e;
      Log.e(e.toString());
      return false;
    }
  }
}