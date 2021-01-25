# bitmap

`BitMap` is an alternative to `Image.file`, achieving higher performance image display.

Use the native texture and texture caching mechanism to render images to achieve the ultimate optimization of image rendering performance. Compared with flutter's native `Image.file`, users can display images more efficiently and concisely.

Using `BitMap` instead of `Image.file`, you will get:

- No longer worry about the problem that pictures cannot be displayed in time when the album is sliding at high speed.

## Parameters
| parameter name | dtype  | description                             | defaults     |
| ---            | ---    | ---                                     | ---          |
| path           | String | image path                              | -            |
| width          | double | the width of the image to be displayed  | -            |
| height         | double | the height of the image to be displayed | -            |
| fit            | BoxFit | image filling method                    | BoxFit.cover |

## Usage
- How to use `BitMap`
```dart
BitMap(
  path: path,
  width: width.toDouble(),
  height: height.toDouble(),
  fit: BoxFit.cover,
)
```

## NOTE
`BitMap` will cache part of the texture during use. After `BitMap` is used, you can choose whether to call `BitMapNaive.dispose` to destroy the cached texture. If it is not destroyed, it will be used next time you use `BitMap` Cached texture, so as to achieve the ultimate optimization of rendering performance.

In some extreme cases, `BitMapNaive.dispose` may not actually destroy all textures.
  - When a certain texture in a BitMap is not loaded, call BitMapNaive.dispose, then the image texture in BitMap will not be destroyed, you can only call BitMapNaive.dispose again after it is loaded To really destroy it
  - Call `BitMapNaive.dispose` when each texture is being used by `BitMap`, then the texture will not be destroyed

## TODO
* [ ] `BitMapNaive.dispose` destroys all created textures
* [ ] Optimized the judgment conditions of `_BitMapState.didUpdateWidget`, and unnecessary rendering after taking out the parent node and calling `setState`
