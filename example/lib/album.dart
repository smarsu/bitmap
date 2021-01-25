import 'dart:io';
import 'dart:typed_data';

import 'package:bitmap/bitmap.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:storages/storages.dart';

class Album extends StatefulWidget {
  @override
  _AlbumState createState() => _AlbumState();
}

class _AlbumState extends State<Album> {
  ScrollController controller;
  List<String> list = [];

  int width = 200;
  int height = 200;

  bool compare = false;
  String comparePath;

  bool isBitMap = true;

  FixSizedStorage fixSizedStorage;

  @override
  void initState() {
    super.initState();
    controller = ScrollController();
    init();
  }

  @override
  void dispose() {
    controller?.dispose();
    for (var path in list) {
      File(path).deleteSync();
    }
    super.dispose();
  }

  init() async {
    fixSizedStorage = FixSizedStorage('albumTest'); 
    await fixSizedStorage.init();

    var result = await PhotoManager.requestPermission();
    print('PhotoManager requestPermission ... $result');

    if (result) {
      List<AssetPathEntity> assetPathEntityList = await PhotoManager.getAssetPathList();
      for (var assetPathEntity in assetPathEntityList) {
        List<AssetEntity> assetEntityList = await assetPathEntity.assetList;
        for (var assetEntity in assetEntityList) {
          // if (assetEntity.type == AssetType.video) {
            // String path = await getApplicationDocumentsPath();
            print(assetEntity.id);
            if (assetEntity.width > 0 && assetEntity.height > 0) {
              String key = assetEntity.id.replaceAll('/', '_');
              String path = await fixSizedStorage.get(key);
              if (path == null) {
                path = await fixSizedStorage.touch(key);
                Uint8List thumbData = await assetEntity.thumbDataWithSize(width, height);
                File(path).writeAsBytesSync(thumbData);
                await fixSizedStorage.set(key, path);
              }
              list.add(path);
            }
          // }
          // else {
          //   String path = (await assetEntity.originFile).path;
          //   list.add(path);
          // }
        }
      }
      setState(() {});
    }
    print('end');

    await convert();
  }

  convert() async {
    while (true) {
      isBitMap = !isBitMap;
      setState(() {});

      /// Wait for finish [setState].
      await Future.delayed(Duration(milliseconds: 200));

      if (!isBitMap) {
        await BitMapNaive.dispose();
      }

      // /// Wait for finish [setState].
      // await Future.delayed(Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GridView.builder(
          padding: EdgeInsets.all(1),
          controller: controller,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
            childAspectRatio: 1,
          ), 
          itemCount: list.length * 100000,
          itemBuilder: (BuildContext context, int index) {
            index = index % list.length;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  comparePath = list[index];
                  compare = true;
                });
              },
              child: isBitMap
                  ? BitMap(
                      path: list[index],
                      width: width.toDouble(),
                      height: height.toDouble(),
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      File(list[index]),
                      width: width.toDouble(),
                      height: height.toDouble(),
                      fit: BoxFit.cover,
                    ),
              // child: BitMap(
              //   path: list[index],
              //   width: width.toDouble(),
              //   height: height.toDouble(),
              //   fit: BoxFit.cover,
              // ),
              // child: Image.file(
              //   File(list[index]),
              //   width: width.toDouble(),
              //   height: height.toDouble(),
              //   fit: BoxFit.cover,
              // ),
            );
            // return Image.file(
            //   File(list[index]),
            //   width: width.toDouble(),
            //   height: height.toDouble(),
            //   fit: BoxFit.cover,
            // );
          }
        ),
        compare
            ? Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      compare = false;
                    });
                  },
                  child: Image.file(
                    File(comparePath),
                    // width: width.toDouble(),
                    // height: height.toDouble(),
                    fit: BoxFit.cover,
                  ),
                )
              )
            : Container(width: 0, height: 0,),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              controller.animateTo(controller.offset + 8000 * 10, duration: Duration(milliseconds: 1000 * 10), curve: Curves.linear);
            },
            onLongPress: () {
              // controller.jumpTo(0);
              isBitMap = !isBitMap;
              setState(() {});
            },
            child: Container(
              alignment: Alignment.bottomCenter,
              height: 60,
              color: Colors.blue,
              child: Center(
                child: Text(isBitMap ? 'BitMap' : 'Flutter Image'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
