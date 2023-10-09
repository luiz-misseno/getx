import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_notifier.dart';

import '../../../get_core/get_core.dart';
import '../../../get_instance/src/get_instance.dart';
import '../../../get_instance/src/lifecycle.dart';
import '../../../get_rx/src/rx_types/rx_types.dart';
import '../simple/list_notifier.dart';

typedef GetXControllerBuilder<T extends GetLifeCycleMixin> = Widget Function(
    T controller);

class GetX<T extends GetLifeCycleMixin> extends StatefulWidget {
  final GetXControllerBuilder<T> builder;
  final bool global;
  final bool autoRemove;
  final bool assignId;
  final void Function(GetXState<T> state)? initState,
      dispose,
      didChangeDependencies;
  final void Function(GetX oldWidget, GetXState<T> state)? didUpdateWidget;
  final T? init;
  final String? tag;
  final bool restorable;
  final String? restorationId;

  const GetX({
    this.tag,
    required this.builder,
    this.global = true,
    this.autoRemove = true,
    this.initState,
    this.assignId = false,
    //  this.stream,
    this.dispose,
    this.didChangeDependencies,
    this.didUpdateWidget,
    this.init,
    // this.streamController
    this.restorable = false,
    this.restorationId,
  });

  @override
  StatefulElement createElement() => StatefulElement(this);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<T>('controller', init),
      )
      ..add(DiagnosticsProperty<String>('tag', tag))
      ..add(
          ObjectFlagProperty<GetXControllerBuilder<T>>.has('builder', builder));
  }

  @override
  GetXState<T> createState() =>
      restorable ? RestorableGetXState<T>() : GetXState<T>();
}

class GetXState<T extends GetLifeCycleMixin> extends State<GetX<T>> {
  GetXState() {
    _observer = GetListenable(null);
  }
  RxInterface? _observer;
  T? controller;
  bool? _isCreator = false;
  late StreamSubscription _subs;

  @override
  void initState() {
    // var isPrepared = GetInstance().isPrepared<T>(tag: widget.tag);
    final isRegistered = GetInstance().isRegistered<T>(tag: widget.tag);

    if (widget.global) {
      if (isRegistered) {
        _isCreator = GetInstance().isPrepared<T>(tag: widget.tag);
        controller = GetInstance().find<T>(tag: widget.tag);
      } else {
        controller = widget.init;
        _isCreator = true;
        GetInstance().put<T>(controller!, tag: widget.tag);
      }
    } else {
      controller = widget.init;
      _isCreator = true;
      controller?.onStart();
    }
    widget.initState?.call(this);
    if (widget.global && Get.smartManagement == SmartManagement.onlyBuilder) {
      controller?.onStart();
    }

    _subs = _observer!.listen((data) => setState(() {}), cancelOnError: false);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.didChangeDependencies != null) {
      widget.didChangeDependencies!(this);
    }
  }

  @override
  void didUpdateWidget(GetX oldWidget) {
    super.didUpdateWidget(oldWidget as GetX<T>);
    widget.didUpdateWidget?.call(oldWidget, this);
  }

  @override
  void dispose() {
    if (widget.dispose != null) widget.dispose!(this);
    if (_isCreator! || widget.assignId) {
      if (widget.autoRemove && GetInstance().isRegistered<T>(tag: widget.tag)) {
        GetInstance().delete<T>(tag: widget.tag);
      }
    }

    for (final disposer in disposers) {
      disposer();
    }

    disposers.clear();
    _subs.cancel();
    _observer?.close();
    controller = null;
    _isCreator = null;
    super.dispose();
  }

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  final disposers = <Disposer>[];

  @override
  Widget build(BuildContext context) => Notifier.instance.append(
      NotifyData(disposers: disposers, updater: _update),
      () => widget.builder(controller!));

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<T>('controller', controller));
  }
}

class RestorableGetXState<T extends GetLifeCycleMixin> extends GetXState<T>
    with RestorationMixin {
  late RestorableDisposableInterface _restorableController;

  StreamSubscription? _changeSubscription;

  @override
  void initState() {
    super.initState();

    if (controller is DisposableInterfaceRestoration) {
      _restorableController = RestorableDisposableInterface(
        (controller as DisposableInterfaceRestoration),
      );

      _changeSubscription = _observer!.listen((event) {
        _restorableController.update();
      });
    } else {
      throw """
      [Get] the improper use of a RestorableGetX has been detected. 
      You should only use RestorableGetX with a controller which implements the DisposableInterfaceRestoration mixin.
      """;
    }
  }

  @override
  void dispose() {
    _changeSubscription?.cancel();
    _restorableController.dispose();

    super.dispose();
  }

  @override
  String? get restorationId => widget.restorationId;

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    // Register our property to be saved every time it,
    // or some reactive value inside it changes,
    // and to be restored every time our app is killed by the OS!
    registerForRestoration(_restorableController, 'controller');
  }
}
