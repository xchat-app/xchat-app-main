import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ox_call/ox_call.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';

/// The TURN server calls in a free circle are relayed through when two phones
/// cannot connect directly. A Private Circle has ours; a free circle can call
/// only once its owner adds one here. Saving checks that the server really
/// relays, so a wrong address or password shows up here, not mid-call.
class CallServerPage extends StatefulWidget {
  const CallServerPage({super.key, this.previousPageTitle});

  final String? previousPageTitle;

  @override
  State<CallServerPage> createState() => _CallServerPageState();
}

class _CallServerPageState extends State<CallServerPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _hasServer = false;
  bool _isChecking = false;

  String? get _circleId => LoginManager.instance.currentCircle?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final circleId = _circleId;
    if (circleId == null) return;
    final servers = await IceServerConfig.customServers(circleId);
    if (!mounted || servers.isEmpty) return;
    final server = servers.first;
    setState(() {
      _hasServer = true;
      _urlCtrl.text = server.url;
      _usernameCtrl.text = server.username ?? '';
      _passwordCtrl.text = server.credential ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_usercenter.call_server'),
        previousPageTitle: widget.previousPageTitle,
        autoTrailing: false,
      ),
      isSectionListPage: true,
      body: LoseFocusWrap(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final fields = [
      _field(
        controller: _urlCtrl,
        label: Localized.text('ox_usercenter.url'),
        hint: 'turn:turn.example.com:3478',
        validator: _validateUrl,
        keyboardType: TextInputType.url,
      ),
      _field(
        controller: _usernameCtrl,
        label: Localized.text('ox_usercenter.call_server_username'),
      ),
      _field(
        controller: _passwordCtrl,
        label: Localized.text('ox_usercenter.call_server_password'),
        obscure: true,
      ),
    ];
    final description = Padding(
      padding: EdgeInsets.symmetric(horizontal: CLLayout.horizontalPadding, vertical: 8.px),
      child: CLText.bodySmall(
        Localized.text('ox_usercenter.call_server_description'),
        colorToken: ColorToken.onSurfaceVariant,
        maxLines: null,
      ),
    );
    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                if (PlatformStyle.isUseMaterial)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: CLLayout.horizontalPadding),
                    child: Column(children: fields),
                  )
                else
                  CupertinoListSection.insetGrouped(
                    additionalDividerMargin: 5,
                    children: fields,
                  ),
                description,
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: CLLayout.horizontalPadding,
              right: CLLayout.horizontalPadding,
              bottom: 12.px,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CLButton.filled(
                  text: _isChecking
                      ? Localized.text('ox_usercenter.validating_call_server')
                      : Localized.text('ox_common.complete'),
                  expanded: true,
                  onTap: _isChecking ? null : _save,
                ),
                if (_hasServer)
                  CLButton.text(
                    text: Localized.text('ox_usercenter.remove'),
                    expanded: true,
                    onTap: _isChecking ? null : _remove,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    if (PlatformStyle.isUseMaterial) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8.px),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: validator ?? _validateNotEmpty,
          keyboardType: keyboardType,
          obscureText: obscure,
          autocorrect: false,
          enabled: !_isChecking,
        ),
      );
    }
    return CupertinoTextFormFieldRow(
      prefix: CLText.titleMedium(label, colorToken: ColorToken.onSurface),
      controller: controller,
      placeholder: hint,
      validator: validator ?? _validateNotEmpty,
      keyboardType: keyboardType,
      obscureText: obscure,
      autocorrect: false,
      textAlign: TextAlign.end,
      decoration: const BoxDecoration(),
      enabled: !_isChecking,
    );
  }

  String? _validateNotEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return Localized.text('ox_common.required');
    return null;
  }

  String? _validateUrl(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty) return Localized.text('ox_common.required');
    if (!url.startsWith('turn:') && !url.startsWith('turns:')) {
      return Localized.text('ox_common.invalid_url_format');
    }
    return null;
  }

  Future<void> _save() async {
    final circleId = _circleId;
    if (circleId == null || !(_formKey.currentState?.validate() ?? false)) return;
    final server = ICEServerDBISAR(
      circleId: circleId,
      url: _urlCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      credential: _passwordCtrl.text,
    );
    setState(() => _isChecking = true);
    final works = await IceServerConfig.testTurnServer(server);
    if (!mounted) return;
    if (!works) {
      setState(() => _isChecking = false);
      CommonToast.instance.show(context, Localized.text('ox_usercenter.call_server_failed'));
      return;
    }
    await IceServerConfig.saveCustomServer(circleId, server);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    final circleId = _circleId;
    if (circleId == null) return;
    await IceServerConfig.removeCustomServers(circleId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }
}
