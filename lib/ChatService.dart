import 'dart:convert';

import 'package:http/http.dart';

class ChatService{

  String key;
  ChatService(this.key);

  askChatGPT(List<Map<String,Object>> chatHistory) async {


    final response =
    await post(Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
          'Bearer $key'
        },
        body: jsonEncode({
          "model": "gpt-4o",
          "messages": chatHistory
        }));


    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      return jsonData['choices'][0]['message']['content'];

    } else {
      return "There is an error!";
    }
  }

  generateImages(String prompt) async {


    final response =
    await post(Uri.parse('https://api.openai.com/v1/images/generations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
          'Bearer $key'
        },
        body: jsonEncode({
          "model": "dall-e-3",
          "prompt": prompt,
          "n":1,
          //"size":"256x256"
        }));


    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      List<String> imageUrls = [];
      for(var item in jsonData['data']){
        imageUrls.add(item['url']);
      }
      return imageUrls;

    } else {
      return ["There is an error!"];
    }
  }


  Future<String> audioToText(String filePath) async {
    try {
      final uri = Uri.parse('https://api.openai.com/v1/audio/translations');
      final request = MultipartRequest('POST', uri);

      // Add headers
      request.headers.addAll({
        'Authorization': 'Bearer $key', // Replace with your actual API key
      });

      // Attach file
      request.files.add(await MultipartFile.fromPath('file', filePath));

      // Add model parameter
      request.fields['model'] = 'whisper-1';
    //  request.fields['language'] = 'fr';

      // Send request
      final streamedResponse = await request.send();
      final response = await Response.fromStream(streamedResponse);

      // Check response status
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        print(response.body);
        return jsonData['text'];
      } else {
        print(response.body);
        return "Error: ${response.statusCode}";
      }
    } catch (e) {
      print("Exception: $e");
      return "An error occurred!";
    }
  }
}