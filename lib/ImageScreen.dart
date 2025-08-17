import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

class ImageScreen extends StatefulWidget {
  String url;
  ImageScreen(this.url, {super.key});

  @override
  State<ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  _saveNetworkImage() async {
    var response = await Dio().get(
      widget.url,
      options: Options(responseType: ResponseType.bytes),
    );
    final result = await ImageGallerySaver.saveImage(
      Uint8List.fromList(response.data),
      quality: 80,
      name: "chagptimage",
    );
    print(result);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Image Downloaded Successfully')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: InkWell(
          onTap: () {
            Navigator.pop(context);
          },
          child: Icon(Icons.arrow_back, color: Colors.white),
        ),
        backgroundColor: Colors.black,
        actions: [
          InkWell(
            onTap: () {
              _saveNetworkImage();
            },
            child: Icon(Icons.download_outlined, color: Colors.white),
          ),
        ],
      ),
      body: Center(
        child: Image.network(
          widget.url,
          width: MediaQuery.of(context).size.width,
          fit: BoxFit.fill,
        ),
      ),
    );
  }
}
