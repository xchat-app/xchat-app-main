import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_localizable/ox_localizable.dart';

class TechnologyIntroductionPage extends StatelessWidget {
  const TechnologyIntroductionPage({
    super.key,
    this.previousPageTitle,
  });

  final String? previousPageTitle;

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_chat.technology_introduction'),
        previousPageTitle: previousPageTitle,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.px),
        child: SafeArea(
          child: Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                SizedBox(height: 24.px),
                _buildContent(context),
                SizedBox(height: 24.px),
                _buildFeatures(),
                SizedBox(height: 24.px),
                _buildDeleteGuide(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CLText.headlineSmall(
          Localized.text('ox_chat.tech_intro_subtitle'),
          colorToken: ColorToken.xChat,
        ),
        SizedBox(height: 8.px),
        Container(
          width: 60.px,
          height: 3.px,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ColorToken.xChat.of(context),
                ColorToken.xChat.of(context).withOpacity(0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(2.px),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildContentCard(
          context,
          Localized.text('ox_chat.tech_intro_content_1'),
          Icons.security,
        ),
        SizedBox(height: 16.px),
        _buildContentCard(
          context,
          Localized.text('ox_chat.tech_intro_content_2'),
          Icons.cloud_off,
        ),
        SizedBox(height: 16.px),
        _buildContentCard(
          context,
          Localized.text('ox_chat.tech_intro_content_3'),
          Icons.vpn_key,
        ),
      ],
    );
  }

  Widget _buildContentCard(BuildContext context, String content, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16.px),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.px),
        border: Border.all(
          color: ColorToken.onSurfaceVariant.of(context).withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8.px),
            decoration: BoxDecoration(
              color: ColorToken.xChat.of(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.px),
            ),
            child: Icon(
              icon,
              size: 24.px,
              color: ColorToken.xChat.of(context),
            ),
          ),
          SizedBox(width: 12.px),
          Expanded(
            child: CLText.bodyMedium(
              content,
              maxLines: null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CLText.titleLarge(
          Localized.text('ox_chat.tech_intro_features_title'),
          colorToken: ColorToken.xChat,
        ),
        SizedBox(height: 16.px),
        _buildFeatureItem(
          Localized.text('ox_chat.tech_intro_feature_1'),
          Localized.text('ox_chat.tech_intro_feature_1_desc'),
        ),
        _buildFeatureItem(
          Localized.text('ox_chat.tech_intro_feature_2'),
          Localized.text('ox_chat.tech_intro_feature_2_desc'),
        ),
        _buildFeatureItem(
          Localized.text('ox_chat.tech_intro_feature_3'),
          Localized.text('ox_chat.tech_intro_feature_3_desc'),
        ),
        _buildFeatureItem(
          Localized.text('ox_chat.tech_intro_feature_4'),
          Localized.text('ox_chat.tech_intro_feature_4_desc'),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(String feature, String description) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.px),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 4.px),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLText.titleSmall(feature),
                SizedBox(height: 4.px),
                CLText.bodySmall(
                  description,
                  colorToken: ColorToken.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteGuide(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CLText.titleLarge(
          Localized.text('ox_chat.tech_intro_delete_title'),
          colorToken: ColorToken.xChat,
        ),
        SizedBox(height: 16.px),
        _buildDeleteItem(
          Localized.text('ox_chat.tech_intro_delete_1'),
          Localized.text('ox_chat.tech_intro_delete_1_desc'),
        ),
        _buildDeleteItem(
          Localized.text('ox_chat.tech_intro_delete_2'),
          Localized.text('ox_chat.tech_intro_delete_2_desc'),
        ),
        _buildDeleteItem(
          Localized.text('ox_chat.tech_intro_delete_3'),
          Localized.text('ox_chat.tech_intro_delete_3_desc'),
        ),
        _buildDeleteItem(
          Localized.text('ox_chat.tech_intro_delete_4'),
          Localized.text('ox_chat.tech_intro_delete_4_desc'),
        ),
      ],
    );
  }

  Widget _buildDeleteItem(String title, String description) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.px),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 4.px),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLText.titleSmall(title),
                SizedBox(height: 4.px),
                CLText.bodySmall(
                  description,
                  colorToken: ColorToken.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
