# bitmap

`BitMap`是`Image.file`的替代方案, 实现了更高性能的图片展示

利用原生texture以及texture缓存机制来渲染图片, 实现图片渲染性能的极致优化, 相比于flutter原生的`Image.file`, 用户可以更加高效简洁地展示图片.

使用`BitMap`而非`Image.file`, 你会获得:

- 不再担心相册高速滑动时图片无法及时展示的问题

## 参数
| 参数名  | 类型   | 描述             | 默认值        |
| ---    | ---    | ---              | ---           |
| path   | String | 图片路径          | 无            |
| width  | double | 需要展示的图片宽度 | 无            |
| height | double | 需要展示的图片高度 | 无            |
| fit    | BoxFit | 图片填充方式       | BoxFit.cover ｜

## 使用
- 如何使用`BitMap`
```dart
BitMap(
  path: path,
  width: width.toDouble(),
  height: height.toDouble(),
  fit: BoxFit.cover,
)
```

## 注意
`BitMap`在使用的过程中会缓存部分texture, 在`BitMap`使用完毕后可以选择是否调用`BitMapNaive.dispose`来销毁缓存的texture. 如果不销毁, 那么下次使用`BitMap`时将会使用缓存的texture, 从而达到渲染性能的极致优化.

在某些极端情况下`BitMapNaive.dispose`不一定会真正的销毁所有的texture. 
  - 当某个`BitMap`中的texture未加载完毕时调用`BitMapNaive.dispose`, 那么该`BitMap`中的图片texture则不会被销毁, 你只能在它加载完毕后再次调用`BitMapNaive.dispose`来真正地销毁它
  - 当每个texture正在被`BitMap`使用时调用`BitMapNaive.dispose`, 那么该texture也不会被销毁

## TODO
* [ ] `BitMapNaive.dispose`销毁所有已创建的texture
* [ ] 优化`_BitMapState.didUpdateWidget`的判断条件, 取出父节点调用`setState`后没必要的渲染
