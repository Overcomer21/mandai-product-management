import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'widgets/store_widgets.dart';
import 'widgets/concurrency_test_page.dart';
import 'widgets/customer_account_panel.dart';
import 'widgets/mandai_splash_gate.dart';
import 'features/products/view/commerce_media_dialog.dart';
import 'features/payments/stripe_checkout_client.dart';
import 'features/payments/payment_return_links.dart';

part 'core/api.dart';
part 'core/merchandise_app.dart';
part 'core/shell.dart';
part 'core/shell_catalog.dart';
part 'core/shell_admin.dart';
part 'core/shell_customer.dart';

const apiBase =
    String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');
void main() => runApp(const MerchandiseApp());
