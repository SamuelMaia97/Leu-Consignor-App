import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({
    super.key,
    required this.filePrefix,
  });

  final String filePrefix;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _availableCameras = const [];
  int _selectedCameraIndex = 0;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCameraList();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCameraList() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _availableCameras = const [];
          _initializing = false;
          _error = 'No camera was found on this device.';
        });
        return;
      }

      final preferredIndex = _preferredCameraIndex(cameras);
      _availableCameras = cameras;

      await _selectCamera(preferredIndex, updateAvailableCameras: false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Camera initialization failed: $error';
      });
    }
  }

  int _preferredCameraIndex(List<CameraDescription> cameras) {
    final backIndex = cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    if (backIndex >= 0) return backIndex;

    final frontIndex = cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    if (frontIndex >= 0) return frontIndex;

    return 0;
  }

  Future<void> _selectCamera(
    int cameraIndex, {
    bool updateAvailableCameras = true,
  }) async {
    if (cameraIndex < 0 || cameraIndex >= _availableCameras.length) {
      return;
    }

    final previousController = _controller;

    if (mounted) {
      setState(() {
        _initializing = true;
        _capturing = false;
        _error = null;
        _controller = null;
        _selectedCameraIndex = cameraIndex;
      });
    }

    await previousController?.dispose();

    try {
      if (updateAvailableCameras) {
        _availableCameras = await availableCameras();
      }

      if (_availableCameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = 'No camera was found on this device.';
        });
        return;
      }

      final safeIndex = cameraIndex >= _availableCameras.length
          ? _availableCameras.length - 1
          : cameraIndex;
      final selectedCamera = _availableCameras[safeIndex];

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _selectedCameraIndex = safeIndex;
        _initializing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Camera initialization failed: $error';
      });
    }
  }

  Future<void> _switchToNextCamera() async {
    if (_availableCameras.length < 2 || _initializing || _capturing) {
      return;
    }

    final nextIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
    await _selectCamera(nextIndex);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }

    setState(() => _capturing = true);

    try {
      final image = await controller.takePicture();

      if (!mounted) return;
      Navigator.of(context).pop(image.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'Taking a photo failed: $error';
      });
    }
  }

  String _cameraLabel(CameraDescription camera, int index) {
    String direction;
    switch (camera.lensDirection) {
      case CameraLensDirection.front:
        direction = 'Front';
        break;
      case CameraLensDirection.back:
        direction = 'Back';
        break;
      case CameraLensDirection.external:
        direction = 'External';
        break;
    }

    final name = camera.name.trim();
    if (name.isEmpty) {
      return '$direction camera ${index + 1}';
    }

    return '$direction camera ${index + 1}';
  }

  CameraDescription? get _selectedCamera {
    if (_availableCameras.isEmpty ||
        _selectedCameraIndex < 0 ||
        _selectedCameraIndex >= _availableCameras.length) {
      return null;
    }

    return _availableCameras[_selectedCameraIndex];
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final selectedCamera = _selectedCamera;
    final canChooseCamera = _availableCameras.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Take photo'),
        actions: [
          if (canChooseCamera)
            PopupMenuButton<int>(
              tooltip: 'Choose camera',
              icon: const Icon(Icons.cameraswitch_outlined),
              enabled: !_initializing && !_capturing,
              onSelected: _selectCamera,
              itemBuilder: (context) {
                return List<PopupMenuEntry<int>>.generate(
                  _availableCameras.length,
                  (index) {
                    final camera = _availableCameras[index];
                    final selected = index == _selectedCameraIndex;

                    return PopupMenuItem<int>(
                      value: index,
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_cameraLabel(camera, index)),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _initializing
                    ? const CircularProgressIndicator()
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : controller == null
                            ? const Text('Camera is unavailable.')
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: AspectRatio(
                                          aspectRatio:
                                              controller.value.aspectRatio,
                                          child: CameraPreview(controller),
                                        ),
                                      ),
                                    ),
                                    if (selectedCamera != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Using ${_cameraLabel(selectedCamera, _selectedCameraIndex).toLowerCase()}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  if (canChooseCamera) ...[
                    const SizedBox(width: 12),
                    IconButton.outlined(
                      tooltip: 'Switch camera',
                      onPressed:
                          _initializing || _capturing ? null : _switchToNextCamera,
                      icon: const Icon(Icons.cameraswitch_outlined),
                    ),
                  ],
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _initializing || _error != null || _capturing
                          ? null
                          : _capture,
                      icon: _capturing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      label: Text(_capturing ? 'Capturing…' : 'Capture'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}