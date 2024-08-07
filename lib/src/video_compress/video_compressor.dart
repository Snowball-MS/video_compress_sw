import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lat_hdr_transcoder_v2/lat_hdr_transcoder_v2.dart';
import 'package:video_compress_sw/src/progress_callback/compress_mixin.dart';
import 'package:video_compress_sw/video_compress_sw.dart';

abstract class IVideoCompress extends CompressMixin {}

class _VideoCompressImpl extends IVideoCompress {
  _VideoCompressImpl._() {
    initProcessCallback();
  }

  static _VideoCompressImpl? _instance;
  static final LatHdrTranscoderV2 latHdrTranscoderV2 = LatHdrTranscoderV2();

  static _VideoCompressImpl get instance {
    return _instance ??= _VideoCompressImpl._();
  }

  static void _dispose() {
    _instance = null;
  }
}

// ignore: non_constant_identifier_names
IVideoCompress get VideoCompressSW => _VideoCompressImpl.instance;
//LatHdrTranscoderV2 get LatHdrTranscoderV2 => _VideoCompressImpl.latHdrTranscoderV2;

extension Compress on IVideoCompress {
  void dispose() {
    _VideoCompressImpl._dispose();
  }

  Future<T?> _invoke<T>(String name, [Map<String, dynamic>? params]) async {
    T? result;
    try {
      result = params != null
          ? await channel.invokeMethod(name, params)
          : await channel.invokeMethod(name);
    } on PlatformException catch (e) {
      debugPrint('''Error from VideoCompress: 
      Method: $name
      $e''');
    }
    return result;
  }

  /// getByteThumbnail return [Future<Uint8List>],
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is milliseconds
  Future<Uint8List?> getByteThumbnail(
    String path, {
    int quality = 100,
    int position = 0,
    int maxWidth = 0,
    int maxHeight = 0,
  }) async {
    assert(quality > 1 || quality < 100);

    return await _invoke<Uint8List>('getByteThumbnail', {
      'path': path,
      'quality': quality,
      'position': position == 0 ? -1 : position,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
    });
  }

  /// getFileThumbnail return [Future<File>]
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is milliseconds
  Future<File> getFileThumbnail(
    String path, {
    int quality = 100,
    int position = 0,
    int maxWidth = 0,
    int maxHeight = 0,
  }) async {
    assert(quality > 1 || quality < 100);

    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final filePath = await (_invoke<String>('getFileThumbnail', {
      'path': path,
      'quality': quality,
      'position': position == 0 ? -1 : position,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
    }));

    final file = File(Uri.decodeComponent(filePath!));

    return file;
  }

  /// get media information from [path]
  ///
  /// get media information from [path] return [Future<MediaInfo>]
  ///
  /// ## example
  /// ```dart
  /// final info = await _flutterVideoCompress.getMediaInfo(file.path);
  /// debugPrint(info.toJson());
  /// ```
  Future<MediaInfo> getMediaInfo(String path) async {
    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final jsonStr = await (_invoke<String>('getMediaInfo', {'path': path}));
    final jsonMap = json.decode(jsonStr!);
    return MediaInfo.fromJson(jsonMap);
  }

  /// compress video from [path]
  /// compress video from [path] return [Future<MediaInfo>]
  ///
  /// you can choose its quality by [quality],
  /// determine whether to delete his source file by [deleteOrigin]
  /// optional parameters [startTime] [duration] [includeAudio] [frameRate]
  ///
  /// ## example
  /// ```dart
  /// final info = await _flutterVideoCompress.compressVideo(
  ///   file.path,
  ///   deleteOrigin: true,
  /// );
  /// debugPrint(info.toJson());
  /// ```
  Future<MediaInfo?> compressVideo(
    String path, {
    VideoQuality quality = VideoQuality.DefaultQuality,
    bool deleteOrigin = false,
    int? startTime,
    int? duration,
    bool? includeAudio,
    int frameRate = 30,
  }) async {
    String inputPath = path;
    if (isCompressing) {
      throw StateError('''VideoCompress Error: 
      Method: compressVideo
      Already have a compression process, you need to wait for the process to finish or stop it''');
    }

    if (compressProgress$.notSubscribed) {
      debugPrint('''VideoCompress: You can try to subscribe to the 
      compressProgress\$ stream to know the compressing state.''');
    }

    final bool isHdrVideo = (await isHdr(inputPath)) ?? true;
    if (isHdrVideo && Platform.isAndroid) {
      try {
        final String? sdrVideoPath = await transcoding(inputPath);
        if (sdrVideoPath?.isNotEmpty ?? false) {
          inputPath = sdrVideoPath!;
        }
      } catch (e) {
        log(e.toString());
      }
    }
    // ignore: invalid_use_of_protected_member
    setProcessingStatus(true);
    final jsonStr = await _invoke<String>('compressVideo', {
      'path': inputPath,
      'quality': quality.index,
      'deleteOrigin': deleteOrigin,
      'startTime': startTime,
      'duration': duration,
      'includeAudio': includeAudio,
      'frameRate': frameRate,
    });

    // ignore: invalid_use_of_protected_member
    setProcessingStatus(false);

    if (jsonStr != null) {
      final jsonMap = json.decode(jsonStr);
      return MediaInfo.fromJson(jsonMap);
    } else {
      return null;
    }
  }

  /// stop compressing the file that is currently being compressed.
  /// If there is no compression process, nothing will happen.
  Future<void> cancelCompression() async {
    await _invoke<void>('cancelCompression');
  }

  /// delete the cache folder, please do not put other things
  /// in the folder of this plugin, it will be cleared
  Future<bool?> deleteAllCache() async {
    await _VideoCompressImpl.latHdrTranscoderV2.cleanCache();
    return await _invoke<bool>('deleteAllCache');
  }

  Future<void> setLogLevel(int logLevel) async {
    return await _invoke<void>('setLogLevel', {
      'logLevel': logLevel,
    });
  }

  Future<bool?> isHdr(String path) async {
    return _VideoCompressImpl.latHdrTranscoderV2.isHdr(path);
  }

  Future<String?> transcoding(String path) async {
    return _VideoCompressImpl.latHdrTranscoderV2.transcoding(path);
  }

  Stream<double> streamConvertHdr() {
    return _VideoCompressImpl.latHdrTranscoderV2.onProgress();
  }
}
