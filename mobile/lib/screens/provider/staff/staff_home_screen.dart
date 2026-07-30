import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../appointments/appointment_list_screen.dart';
import '../journal/pro_journal_screen.dart';
import '../profile/pro_profile_screen.dart';

/// The Collaborateur shell (module `access` §5.3 — team access R4b, user
/// decision 2026-07-12): staff — and only staff — get a 3-tab bottom bar,
/// « Journée · Calendrier · Profil ». Journée = the journal in own-mode
/// (locked to the member's artist); Calendrier = the appointment list
/// (own-filtered server-side, T40); Profil = the slim personal profile.
/// One-thumb UX for a worker checking their day; owners/managers/réception
/// keep the hub-and-spoke app.
class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ProJournalScreen(),
          AppointmentListScreen(),
          ProProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.secondary,
        indicatorColor: AppColors.surfaceVariant,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Journée',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendrier',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
