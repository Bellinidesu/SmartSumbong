// SmartSumbong — shared video playback.
//
// Video evidence upload shipped in 0033/media_upload.dart with nothing on
// the other end to play it back: report_view_screen and dispatch_order
// both rendered every report_media/dispatch_media row as Image.network,
// which silently breaks on any video URL (a broken-image icon, not a
// player). report_media_mime_type_check / dispatch_media_mime_type_check
// already store mime_type per row, so isVideoMime is the one place both
// apps need to agree on what counts as video, and the two widgets below
// are the one place both apps need to agree on how to play it.

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

bool isVideoMime(String? mimeType) =>
    mimeType != null && mimeType.startsWith('video/');

/// The actual player, with no Scaffold of its own, so it can sit inside
/// something else's PageView page (report_view_screen's photo/video
/// swiper) or be wrapped in a Scaffold for a standalone route
/// (VideoPlayerScreen, below).
class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({super.key, required this.url});
  final String url;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late final VideoPlayerController _video;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    _video = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: _video,
          autoPlay: false,
          looping: false,
          showControlsOnInitialize: true,
        );
      });
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Could not load this video.');
    });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white)),
      );
    }
    if (_chewie == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _video.value.aspectRatio == 0 ? 16 / 9 : _video.value.aspectRatio,
        child: Chewie(controller: _chewie!),
      ),
    );
  }
}

/// A standalone full-screen route for a single video, for screens (like
/// dispatch_order's evidence pane) that push a new page rather than
/// embedding the player inline.
class VideoPlayerScreen extends StatelessWidget {
  const VideoPlayerScreen({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: InlineVideoPlayer(url: url),
    );
  }
}
