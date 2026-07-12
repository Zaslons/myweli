import 'package:flutter/foundation.dart';

import '../core/access/pro_salon_scope.dart';
import '../core/di/dependency_injection.dart';
import '../models/api_response.dart';
import '../models/team_invitation.dart';
import '../models/team_member.dart';
import '../services/interfaces/pro_team_service_interface.dart';

/// Drives the Équipe screen (owner roster + invite/role/revoke/resend) and
/// the signed-in identity's pending invitations (module `access` R3).
/// Mutations update the row in place from the returned member.
class ProTeamProvider extends ChangeNotifier implements SalonScoped {
  ProTeamServiceInterface get _service => serviceLocator.proTeamService;

  // ---- Owner roster ---------------------------------------------------------

  List<TeamMember> _members = const [];
  bool _isLoading = false;
  String? _error;

  /// Owner pinned first (defensive client-side sort).
  List<TeamMember> get members => _members;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Invite (the sheet's own error surface).
  bool _isInviting = false;
  String? _inviteError;
  String? _inviteErrorCode;

  bool get isInviting => _isInviting;
  String? get inviteError => _inviteError;
  String? get inviteErrorCode => _inviteErrorCode;

  // Row actions (role change / revoke / resend).
  String? _actionError;
  String? _actionErrorCode;

  String? get actionError => _actionError;
  String? get actionErrorCode => _actionErrorCode;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.getMembers();
      if (res.success && res.data != null) {
        _members = _sorted(res.data!);
      } else {
        _error = res.error ?? 'Erreur lors du chargement';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<TeamMember?> invite({
    required String email,
    required TeamRole role,
    String? artistId,
  }) async {
    _isInviting = true;
    _inviteError = null;
    _inviteErrorCode = null;
    notifyListeners();
    try {
      final res = await _service.inviteMember(
        email: email,
        role: role,
        artistId: artistId,
      );
      if (res.success && res.data != null) {
        _members = _sorted([..._members, res.data!]);
        return res.data;
      }
      _inviteError = res.error ?? 'Invitation impossible.';
      _inviteErrorCode = res.code;
      return null;
    } catch (e) {
      _inviteError = e.toString();
      return null;
    } finally {
      _isInviting = false;
      notifyListeners();
    }
  }

  /// Clears the invite error surface (reopening the sheet).
  void resetInviteState() {
    _inviteError = null;
    _inviteErrorCode = null;
    notifyListeners();
  }

  Future<bool> changeRole(
    String memberId, {
    required TeamRole role,
    String? artistId,
  }) =>
      _memberAction(
        () => _service.changeRole(memberId, role: role, artistId: artistId),
      );

  Future<bool> revoke(String memberId) =>
      _memberAction(() => _service.revokeMember(memberId));

  Future<bool> resend(String memberId) =>
      _memberAction(() => _service.resendInvitation(memberId));

  Future<bool> _memberAction(
    Future<ApiResponse<TeamMember>> Function() run,
  ) async {
    _actionError = null;
    _actionErrorCode = null;
    notifyListeners();
    try {
      final res = await run();
      if (res.success && res.data != null) {
        final updated = res.data!;
        _members = _sorted([
          for (final m in _members) m.id == updated.id ? updated : m,
        ]);
        notifyListeners();
        return true;
      }
      _actionError = res.error ?? 'Action impossible.';
      _actionErrorCode = res.code;
      notifyListeners();
      return false;
    } catch (e) {
      _actionError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ---- The invitee side (authed) --------------------------------------------

  List<TeamInvitation> _myInvitations = const [];
  bool _invitationsLoading = false;

  List<TeamInvitation> get myInvitations => _myInvitations;
  int get invitationCount => _myInvitations.length;
  bool get invitationsLoading => _invitationsLoading;

  Future<void> loadMyInvitations() async {
    _invitationsLoading = true;
    notifyListeners();
    try {
      final res = await _service.getMyInvitations();
      if (res.success && res.data != null) {
        _myInvitations = res.data!;
      }
    } catch (_) {
      // Silent — the profile badge simply doesn't show.
    } finally {
      _invitationsLoading = false;
      notifyListeners();
    }
  }

  /// Accept under the current session; the card disappears on success.
  Future<TeamMember?> acceptMyInvitation(String invitationId) async {
    _actionError = null;
    _actionErrorCode = null;
    try {
      final res = await _service.acceptInvitation(invitationId);
      if (res.success && res.data != null) {
        _myInvitations = _myInvitations
            .where((i) => i.id != invitationId)
            .toList(growable: false);
        notifyListeners();
        return res.data;
      }
      _actionError = res.error ?? 'Invitation impossible à accepter.';
      _actionErrorCode = res.code;
      if (res.code == 'invitation_expired' || res.code == 'not_found') {
        _myInvitations = _myInvitations
            .where((i) => i.id != invitationId)
            .toList(growable: false);
      }
      notifyListeners();
      return null;
    } catch (e) {
      _actionError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> declineMyInvitation(String invitationId) async {
    _actionError = null;
    _actionErrorCode = null;
    try {
      final res = await _service.declineInvitation(invitationId);
      if (res.success) {
        _myInvitations = _myInvitations
            .where((i) => i.id != invitationId)
            .toList(growable: false);
        notifyListeners();
        return true;
      }
      _actionError = res.error ?? 'Refus impossible.';
      _actionErrorCode = res.code;
      notifyListeners();
      return false;
    } catch (e) {
      _actionError = e.toString();
      notifyListeners();
      return false;
    }
  }

  static List<TeamMember> _sorted(List<TeamMember> rows) {
    final list = List<TeamMember>.from(rows);
    list.sort((a, b) {
      if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
      return a.invitedAt.compareTo(b.invitedAt);
    });
    return list;
  }

  /// R6 multi-salons: drop the previous salon's data on a switch.
  @override
  void resetForSalonSwitch() {
    _members = const [];
    _isLoading = false;
    _error = null;
    _isInviting = false;
    _inviteError = null;
    _inviteErrorCode = null;
    _actionError = null;
    _actionErrorCode = null;
    _myInvitations = const [];
    _invitationsLoading = false;
    notifyListeners();
  }
}
