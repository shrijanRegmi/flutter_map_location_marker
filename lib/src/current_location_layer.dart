import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';

import 'data.dart';
import 'data_stream_factory.dart';
import 'exception/incorrect_setup_exception.dart';
import 'exception/permission_denied_exception.dart';
import 'exception/permission_requesting_exception.dart';
import 'exception/service_disabled_exception.dart';
import 'follow_on_location_update.dart';
import 'indicators.dart';
import 'location_marker_layer.dart';
import 'non_rotation_container.dart';
import 'style.dart';
import 'turn_on_heading_update.dart';
import 'tween.dart';

const _originPoint = Point<double>(0, 0);

/// A layer for current location marker in [FlutterMap].
class CurrentLocationLayer extends StatefulWidget {
  /// The style to use for this location marker.
  final LocationMarkerStyle style;

  /// A Stream that provide position data for this marker. Default to
  /// [LocationMarkerDataStreamFactory.fromGeolocatorPositionStream].
  final Stream<LocationMarkerPosition?> positionStream;

  /// A Stream that provide heading data for this marker. Default to
  /// [LocationMarkerDataStreamFactory.fromCompassHeadingStream].
  final Stream<LocationMarkerHeading?> headingStream;

  /// A screen point that when the map follow to the marker. The point
  /// (-1.0, -1.0) indicate the top-left corner of the map widget. The point
  /// (+1.0, +1.0) indicate the bottom-right corner of the map widget. The point
  /// (0.0, 0.0) indicate the center of the map widget. The final screen point
  /// is offset by [followScreenPointOffset], i.e. (_mapWidgetWidth_ *
  /// [followScreenPoint.x] / 2 + [followScreenPointOffset.x],
  /// _mapWidgetHeight_ * [followScreenPoint.y] / 2 + [followScreenPointOffset.y]).
  final Point<double> followScreenPoint;

  /// An offset value that when the map follow to the marker. The final screen
  /// point is (_mapWidgetWidth_ * [followScreenPoint.x] / 2 +
  /// [followScreenPointOffset.x], _mapWidgetHeight_ * [followScreenPoint.y] /
  /// 2 + [followScreenPointOffset.y]).
  final Point<double> followScreenPointOffset;

  /// The event stream for follow current location. Add a zoom level into
  /// this stream to follow the current location at the provided zoom level or a
  /// null if the zoom level should be unchanged. Default to null.
  ///
  /// For more details, see
  /// [FollowFabExample](https://github.com/tlserver/flutter_map_location_marker/blob/master/example/lib/page/follow_fab_example.dart).
  final Stream<double?>? followCurrentLocationStream;

  /// The event stream for turning heading up. Default to null.
  final Stream<void>? turnHeadingUpLocationStream;

  /// When should the map follow current location. Default to
  /// [FollowOnLocationUpdate.never].
  final FollowOnLocationUpdate followOnLocationUpdate;

  /// When should the plugin rotate the map to keep the heading upward. Default
  /// to [TurnOnHeadingUpdate.never].
  final TurnOnHeadingUpdate turnOnHeadingUpdate;

  /// The duration of the animation of following the map to the current
  /// location. Default to 200ms.
  final Duration followAnimationDuration;

  /// The curve of the animation of following the map to the current location.
  /// Default to [Curves.fastOutSlowIn].
  final Curve followAnimationCurve;

  /// The duration of the animation of turning the map to align the heading.
  /// Default to 200ms.
  final Duration turnAnimationDuration;

  /// The curve of the animation of turning the map to align the heading.
  /// Default to [Curves.easeInOut].
  final Curve turnAnimationCurve;

  /// The duration of the marker's move animation. Default to 200ms.
  final Duration moveAnimationDuration;

  /// The curve of the marker's move animation. Default to
  /// [Curves.fastOutSlowIn].
  final Curve moveAnimationCurve;

  /// The duration of the heading sector rotate animation. Default to 200ms.
  final Duration rotateAnimationDuration;

  /// The curve of the heading sector rotate animation. Default to
  /// [Curves.easeInOut].
  final Curve rotateAnimationCurve;

  /// The indicators which will display when in special status.
  final LocationMarkerIndicators indicators;

  /// Create a CurrentLocationLayer.
  CurrentLocationLayer({
    super.key,
    this.style = const LocationMarkerStyle(),
    Stream<LocationMarkerPosition?>? positionStream,
    Stream<LocationMarkerHeading?>? headingStream,
    this.followScreenPoint = _originPoint,
    this.followScreenPointOffset = _originPoint,
    this.followCurrentLocationStream,
    this.turnHeadingUpLocationStream,
    this.followOnLocationUpdate = FollowOnLocationUpdate.never,
    this.turnOnHeadingUpdate = TurnOnHeadingUpdate.never,
    this.followAnimationDuration = const Duration(milliseconds: 200),
    this.followAnimationCurve = Curves.fastOutSlowIn,
    this.turnAnimationDuration = const Duration(milliseconds: 200),
    this.turnAnimationCurve = Curves.easeInOut,
    this.moveAnimationDuration = const Duration(milliseconds: 200),
    this.moveAnimationCurve = Curves.fastOutSlowIn,
    this.rotateAnimationDuration = const Duration(milliseconds: 200),
    this.rotateAnimationCurve = Curves.easeInOut,
    this.indicators = const LocationMarkerIndicators(),
  })  : positionStream = positionStream ??
            const LocationMarkerDataStreamFactory()
                .fromGeolocatorPositionStream(),
        headingStream = headingStream ??
            const LocationMarkerDataStreamFactory().fromCompassHeadingStream();

  @override
  State<CurrentLocationLayer> createState() => _CurrentLocationLayerState();
}

class _CurrentLocationLayerState extends State<CurrentLocationLayer>
    with TickerProviderStateMixin {
  _Status _status = _Status.initialing;
  LocationMarkerPosition? _currentPosition;
  LocationMarkerHeading? _currentHeading;
  double? _followingZoom;

  late bool _isFirstLocationUpdate;
  late bool _isFirstHeadingUpdate;

  late StreamSubscription<LocationMarkerPosition?> _positionStreamSubscription;
  late StreamSubscription<LocationMarkerHeading?> _headingStreamSubscription;

  /// Subscription to a stream for following single that also include a zoom
  /// level.
  StreamSubscription<double?>? _followCurrentLocationStreamSubscription;

  /// Subscription to a stream for single indicate turning the heading up.
  StreamSubscription<void>? _turnHeadingUpStreamSubscription;

  AnimationController? _moveMapAnimationController;
  AnimationController? _moveMarkerAnimationController;
  AnimationController? _rotateMapAnimationController;
  AnimationController? _rotateMarkerAnimationController;

  @override
  void initState() {
    super.initState();
    _isFirstLocationUpdate = true;
    _isFirstHeadingUpdate = true;
    _subscriptPositionStream();
    _subscriptHeadingStream();
    _subscriptFollowCurrentLocationStream();
    _subscriptTurnHeadingUpStream();
  }

  @override
  void didUpdateWidget(CurrentLocationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.positionStream != oldWidget.positionStream) {
      _positionStreamSubscription.cancel();
      _subscriptPositionStream();
    }
    if (widget.headingStream != oldWidget.headingStream) {
      _headingStreamSubscription.cancel();
      _subscriptHeadingStream();
    }
    if (widget.followCurrentLocationStream !=
        oldWidget.followCurrentLocationStream) {
      _followCurrentLocationStreamSubscription?.cancel();
      _subscriptFollowCurrentLocationStream();
    }
    if (widget.turnHeadingUpLocationStream !=
        oldWidget.turnHeadingUpLocationStream) {
      _turnHeadingUpStreamSubscription?.cancel();
      _subscriptTurnHeadingUpStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _Status.initialing:
        return const SizedBox.shrink();
      case _Status.ready:
        if (_currentPosition != null) {
          return LocationMarkerLayer(
            position: _currentPosition!,
            heading: _currentHeading,
            style: widget.style,
          );
        } else {
          return const SizedBox.shrink();
        }
      case _Status.incorrectSetup:
        if (kDebugMode) {
          return NonRotationContainer(
            child: SizedBox.expand(
              child: ColoredBox(
                color: Colors.red.withAlpha(0x80),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'LocationMarker plugin has not been setup correctly. '
                    'Please follow the instructions in the documentation.',
                    style: TextStyle(fontSize: 26),
                  ),
                ),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      case _Status.permissionRequesting:
        if (widget.indicators.permissionRequesting != null) {
          return NonRotationContainer(
            child: widget.indicators.permissionRequesting!,
          );
        }
        if (kDebugMode) {
          return const NonRotationContainer(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Location Access Permission Requesting\n'
                  '(Debug Mode Only)',
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      case _Status.permissionDenied:
        if (widget.indicators.permissionDenied != null) {
          return NonRotationContainer(
            child: widget.indicators.permissionDenied!,
          );
        }
        if (kDebugMode) {
          return const NonRotationContainer(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Location Access Permission Denied\n'
                  '(Debug Mode Only)',
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      case _Status.serviceDisabled:
        if (widget.indicators.serviceDisabled != null) {
          return NonRotationContainer(
            child: widget.indicators.serviceDisabled!,
          );
        }
        if (kDebugMode) {
          return const NonRotationContainer(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Location Service Disabled\n'
                  '(Debug Mode Only)',
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription.cancel();
    _headingStreamSubscription.cancel();
    _followCurrentLocationStreamSubscription?.cancel();
    _turnHeadingUpStreamSubscription?.cancel();
    _moveMapAnimationController?.dispose();
    _moveMarkerAnimationController?.dispose();
    _rotateMapAnimationController?.dispose();
    _rotateMarkerAnimationController?.dispose();
    super.dispose();
  }

  void _subscriptPositionStream() {
    _positionStreamSubscription = widget.positionStream.listen(
      (LocationMarkerPosition? position) {
        if (position == null) {
          if (_status != _Status.initialing) {
            setState(() {
              _status = _Status.initialing;
              _currentPosition = null;
            });
          }
        } else {
          if (_status != _Status.ready) {
            setState(() {
              _status = _Status.ready;
            });
          }
          _moveMarker(position);

          bool followCurrentLocation;
          switch (widget.followOnLocationUpdate) {
            case FollowOnLocationUpdate.always:
              followCurrentLocation = true;
            case FollowOnLocationUpdate.once:
              followCurrentLocation = _isFirstLocationUpdate;
              _isFirstLocationUpdate = false;
            case FollowOnLocationUpdate.never:
              followCurrentLocation = false;
          }
          if (followCurrentLocation) {
            _moveMap(
              position.latLng,
              _followingZoom,
            );
          }
        }
      },
      onError: (error) {
        switch (error) {
          case IncorrectSetupException _:
            setState(() => _status = _Status.incorrectSetup);
          case PermissionRequestingException _:
            setState(() => _status = _Status.permissionRequesting);
          case PermissionDeniedException _:
            setState(() => _status = _Status.permissionDenied);
          case ServiceDisabledException _:
            setState(() => _status = _Status.serviceDisabled);
        }
      },
    );
  }

  void _subscriptHeadingStream() {
    _headingStreamSubscription = widget.headingStream.listen(
      (LocationMarkerHeading? heading) {
        if (heading == null) {
          if (_currentHeading != null) {
            setState(() => _currentHeading = null);
          }
        } else {
          _rotateMarker(heading);

          bool turnHeadingUp;
          switch (widget.turnOnHeadingUpdate) {
            case TurnOnHeadingUpdate.always:
              turnHeadingUp = true;
            case TurnOnHeadingUpdate.once:
              turnHeadingUp = _isFirstHeadingUpdate;
              _isFirstHeadingUpdate = false;
            case TurnOnHeadingUpdate.never:
              turnHeadingUp = false;
          }
          if (turnHeadingUp) {
            _rotateMap(-heading.heading % (2 * pi));
          }
        }
      },
      onError: (_) {
        if (_currentHeading != null) {
          setState(() => _currentHeading = null);
        }
      },
    );
  }

  void _subscriptFollowCurrentLocationStream() {
    _followCurrentLocationStreamSubscription =
        widget.followCurrentLocationStream?.listen((double? zoom) {
      if (_currentPosition != null) {
        _followingZoom = zoom;
        _moveMap(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          zoom,
        ).whenComplete(() => _followingZoom = null);
      }
    });
  }

  void _subscriptTurnHeadingUpStream() {
    _turnHeadingUpStreamSubscription =
        widget.turnHeadingUpLocationStream?.listen((_) {
      if (_currentHeading != null) {
        _rotateMap(-_currentHeading!.heading % (2 * pi));
      }
    });
  }

  TickerFuture _moveMarker(LocationMarkerPosition position) {
    _moveMarkerAnimationController?.dispose();
    _moveMarkerAnimationController = AnimationController(
      duration: widget.moveAnimationDuration,
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: _moveMarkerAnimationController!,
      curve: widget.moveAnimationCurve,
    );
    final positionTween = LocationMarkerPositionTween(
      begin: _currentPosition ?? position,
      end: position,
    );

    _moveMarkerAnimationController!.addListener(() {
      setState(() => _currentPosition = positionTween.evaluate(animation));
    });

    _moveMarkerAnimationController!.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _moveMarkerAnimationController!.dispose();
        _moveMarkerAnimationController = null;
      }
    });

    return _moveMarkerAnimationController!.forward();
  }

  TickerFuture _moveMap(LatLng latLng, [double? zoom]) {
    final mapCamera = MapCamera.of(context);
    final mapController = MapController.of(context);
    zoom ??= mapCamera.zoom;

    final LatLng beginLatLng;
    if (widget.followScreenPoint == _originPoint &&
        widget.followScreenPointOffset == _originPoint) {
      beginLatLng = mapCamera.center;
    } else {
      final crs = mapCamera.crs;
      final followOffset =
          (mapCamera.nonRotatedSize * 0.5).scaleBy(widget.followScreenPoint) +
              widget.followScreenPointOffset;
      final mapCenter = crs.latLngToPoint(mapCamera.center, mapCamera.zoom);
      final followPoint =
          mapCamera.rotatePoint(mapCenter, mapCenter + followOffset);
      beginLatLng = crs.pointToLatLng(followPoint, mapCamera.zoom);
    }

    _moveMapAnimationController?.dispose();
    _moveMapAnimationController = AnimationController(
      duration: widget.followAnimationDuration,
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: _moveMapAnimationController!,
      curve: widget.followAnimationCurve,
    );
    final latTween = Tween(
      begin: beginLatLng.latitude,
      end: latLng.latitude,
    );
    final lngTween = Tween(
      begin: beginLatLng.longitude,
      end: latLng.longitude,
    );
    final zoomTween = Tween(
      begin: mapCamera.zoom,
      end: zoom,
    );

    _moveMapAnimationController!.addListener(() {
      final evaluatedLatLng = LatLng(
        latTween.evaluate(animation),
        lngTween.evaluate(animation),
      );
      final evaluatedZoom = zoomTween.evaluate(animation);

      final LatLng mapCenter;
      if (widget.followScreenPoint == _originPoint &&
          widget.followScreenPointOffset == _originPoint) {
        mapCenter = evaluatedLatLng;
      } else {
        final crs = mapCamera.crs;
        final followOffset =
            (mapCamera.nonRotatedSize * 0.5).scaleBy(widget.followScreenPoint) +
                widget.followScreenPointOffset;
        final followPoint = crs.latLngToPoint(evaluatedLatLng, evaluatedZoom);
        final mapCenterPoint = mapCamera.rotatePoint(
          followPoint,
          followPoint - followOffset,
        );
        mapCenter = crs.pointToLatLng(mapCenterPoint, evaluatedZoom);
      }

      mapController.move(
        mapCenter,
        evaluatedZoom,
      );
    });

    _moveMapAnimationController!.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _moveMapAnimationController!.dispose();
        _moveMapAnimationController = null;
      }
    });

    return _moveMapAnimationController!.forward();
  }

  TickerFuture _rotateMarker(LocationMarkerHeading heading) {
    _rotateMarkerAnimationController?.dispose();
    _rotateMarkerAnimationController = AnimationController(
      duration: widget.rotateAnimationDuration,
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: _rotateMarkerAnimationController!,
      curve: widget.rotateAnimationCurve,
    );
    final headingTween = LocationMarkerHeadingTween(
      begin: _currentHeading ?? heading,
      end: heading,
    );

    _rotateMarkerAnimationController!.addListener(() {
      if (_status == _Status.ready) {
        setState(() => _currentHeading = headingTween.evaluate(animation));
      }
    });

    _rotateMarkerAnimationController!
        .addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _rotateMarkerAnimationController!.dispose();
        _rotateMarkerAnimationController = null;
      }
    });

    return _rotateMarkerAnimationController!.forward();
  }

  TickerFuture _rotateMap(double angle) {
    final mapCamera = MapCamera.of(context);
    final mapController = MapController.of(context);

    _rotateMapAnimationController?.dispose();
    if ((mapCamera.rotationRad - angle).abs() < 0.006) {
      _rotateMapAnimationController = null;
      return TickerFuture.complete();
    }
    _rotateMapAnimationController = AnimationController(
      duration: widget.turnAnimationDuration,
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: _rotateMapAnimationController!,
      curve: widget.turnAnimationCurve,
    );
    final angleTween = RadiusTween(
      begin: mapCamera.rotationRad,
      end: angle,
    );

    _rotateMapAnimationController!.addListener(() {
      if (widget.followScreenPoint == _originPoint &&
          widget.followScreenPointOffset == _originPoint) {
        mapController.rotate(
          angleTween.evaluate(animation) / pi * 180,
        );
      } else {
        final crs = mapCamera.crs;
        final followOffset =
            (mapCamera.nonRotatedSize * 0.5).scaleBy(widget.followScreenPoint) +
                widget.followScreenPointOffset;
        final mapCenter = crs.latLngToPoint(mapCamera.center, mapCamera.zoom);
        final followPoint =
            mapCamera.rotatePoint(mapCenter, mapCenter + followOffset);
        mapController.rotate(
          angleTween.evaluate(animation) / pi * 180,
        );
        final mapCenterPoint = mapCamera.rotatePoint(
          followPoint,
          followPoint - followOffset,
        );
        final offsetMapCenter =
            crs.pointToLatLng(mapCenterPoint, mapCamera.zoom);
        mapController.move(
          offsetMapCenter,
          mapCamera.zoom,
        );
      }
    });

    _rotateMapAnimationController!.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _rotateMapAnimationController!.dispose();
        _rotateMapAnimationController = null;
      }
    });

    return _rotateMapAnimationController!.forward();
  }
}

enum _Status {
  initialing,
  incorrectSetup,
  serviceDisabled,
  permissionRequesting,
  permissionDenied,
  ready,
}
