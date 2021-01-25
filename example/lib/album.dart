import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bitmap/bitmap.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:storages/storages.dart';

/// Scroll physics for limit the max velocity to be 16000.
class BouncingScrollPhysicsEx extends BouncingScrollPhysics {
  const BouncingScrollPhysicsEx({ ScrollPhysics parent }) : super(parent: parent);

  @override
  BouncingScrollPhysicsEx applyTo(ScrollPhysics ancestor) {
    return BouncingScrollPhysicsEx(parent: buildParent(ancestor));
  }

  @override
  double carriedMomentum(double existingVelocity) {
    return existingVelocity.sign *
        min(0.000816 * pow(existingVelocity.abs(), 1.967).toDouble(), 8000);
  }
}

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

    /// The speed slide by handle can be larger than 50k.
    /// 
    /// Use [BouncingScrollPhysicsEx] to limit the maximum speed.
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      print('velocity: ${controller?.position?.activity?.velocity}');
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    BitMapNaive.dispose();
    super.dispose();
  }

  init() async {
    fixSizedStorage = FixSizedStorage('albumTest');
    await fixSizedStorage.init();

    var result = await PhotoManager.requestPermission();
    print('PhotoManager requestPermission ... $result');

    if (result) {
      List<AssetPathEntity> assetPathEntityList =
          await PhotoManager.getAssetPathList();
      for (var assetPathEntity in assetPathEntityList) {
        List<AssetEntity> assetEntityList = await assetPathEntity.assetList;
        for (var assetEntity in assetEntityList) {
          if (assetEntity.width > 0 && assetEntity.height > 0) {
            String key = assetEntity.id.replaceAll('/', '_');
            String path = await fixSizedStorage.get(key);
            if (path == null) {
              path = await fixSizedStorage.touch(key);
              Uint8List thumbData =
                  await assetEntity.thumbDataWithSize(width, height);
              File(path).writeAsBytesSync(thumbData);
              await fixSizedStorage.set(key, path);
            }
            list.add(path);
          }
        }
      }
      setState(() {});
    }

    // // For test dispose.
    // await convert();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GridView.builder(
            padding: EdgeInsets.all(1),
            controller: controller,
            physics:  BouncingScrollPhysicsEx(),
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
              );
            }),
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
                    fit: BoxFit.cover,
                  ),
                ))
            : Container(
                width: 0,
                height: 0,
              ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              controller.animateTo(controller.offset + 8000 * 10,
                  duration: Duration(milliseconds: 1000 * 10),
                  curve: Curves.linear);
            },
            onLongPress: () {
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
