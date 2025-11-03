import 'package:flutter/material.dart';

import '../modules/admin/admin_dashboard.dart';

class AdminPortalPage extends StatelessWidget {
  const AdminPortalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppBar(title: Text('Admin Portal')),
      body: AdminDashboardView(),
    );
  }
}
