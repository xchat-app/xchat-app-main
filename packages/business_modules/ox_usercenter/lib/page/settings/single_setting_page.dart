
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_localizable/ox_localizable.dart';

class SingleSettingPage extends StatefulWidget {
  const SingleSettingPage({
    super.key,
    this.previousPageTitle,
    this.title,
    this.initialValue = '',
    required this.saveAction,
    this.maxLines = 1,
    this.textInputAction = TextInputAction.done,
  });

  final String? previousPageTitle;
  final String? title;
  final String initialValue;
  final int? maxLines;
  final TextInputAction textInputAction;

  final Function(BuildContext ctx, String value) saveAction;

  @override
  State<StatefulWidget> createState() => SingleSettingPageState();
}

class SingleSettingPageState extends State<SingleSettingPage> {

  final TextEditingController controller = TextEditingController();

  @override
  void initState() {
    super.initState();

    controller.text = widget.initialValue;
    controller.selection = TextSelection.collapsed(offset: widget.initialValue.length);
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: widget.title,
        previousPageTitle: widget.previousPageTitle,
        autoTrailing: false,
        actions: [
          if (!PlatformStyle.isUseMaterial)
            CLButton.text(
              text: Localized.text('ox_common.save'),
              onTap: () => widget.saveAction(context, controller.text),
            ),
        ],
      ),
      body: LoseFocusWrap(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: 16.px,
            vertical: 12.px,
          ),
          children: [
            CLTextField(
              controller: controller,
              autofocus: false,
              placeholder: widget.title,
              maxLines: null,
              textInputAction: widget.textInputAction,
            ),
            SizedBox(height: 20.px,),
            if (PlatformStyle.isUseMaterial)
              CLButton.filled(
                padding: EdgeInsets.symmetric(vertical: 12.px),
                text: Localized.text('ox_common.save'),
                onTap: () => widget.saveAction(context, controller.text),
              )
          ],
        ),
      ),
    );
  }
}