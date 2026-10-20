import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/technician_jobs/data/technician_jobs_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_job.dart';

class TechnicianTestAuthRepository implements AuthRepository {
  TechnicianTestAuthRepository() : profile = technicianProfile();

  UserProfile profile;
  final _sessions = StreamController<bool>.broadcast(sync: true);
  bool _hasSession = true;
  @override
  bool get hasSession => _hasSession;
  set hasSession(bool value) {
    _hasSession = value;
    _sessions.add(value);
  }

  @override
  Stream<bool> get sessionChanges => _sessions.stream;
  @override
  Future<UserProfile> loadProfile() async => profile;
  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    hasSession = true;
    return profile;
  }

  @override
  Future<void> signOut() async => hasSession = false;
  @override
  Future<UserProfile> changePassword({required String newPassword}) async =>
      profile.copyWith(mustChangePassword: false, canAccess: true);
  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
  Future<void> dispose() => _sessions.close();
}

UserProfile technicianProfile({String id = 'technician-1'}) => UserProfile(
  id: id,
  identityCode: 'KTV001',
  fullName: 'Kỹ thuật viên Bình',
  email: 'technician@example.com',
  phone: '0901111111',
  role: AppRole.technician,
  status: 'active',
  room: null,
  mustChangePassword: false,
  canAccess: true,
);

final technicianTestDate = DateTime.utc(2026, 10, 15, 8);

TechnicianJob technicianJob({
  String id = 'job-1',
  String title = 'Vòi nước phòng A101 rò rỉ',
  RepairStatus status = RepairStatus.awaitingRework,
}) => TechnicianJob(
  id: id,
  requestCode: id == 'job-1' ? 'DF000001' : 'DF000002',
  title: title,
  description: 'Ống nối dưới bồn rửa bị nứt.',
  roomCode: 'A101',
  building: 'Tòa nhà A',
  categoryName: 'Nước',
  status: status,
  createdAt: technicianTestDate,
  updatedAt: technicianTestDate,
  version: 2,
);

JobAttachment technicianAttachment(
  String id, {
  String? resultId,
  String? feedbackId,
}) => JobAttachment(
  id: id,
  storagePath: 'job-1/$id.png',
  mimeType: 'image/png',
  sizeBytes: 70,
  resultId: resultId,
  feedbackId: feedbackId,
);

TechnicianJobDetail technicianDetail({
  RepairStatus status = RepairStatus.awaitingRework,
  bool withPhotos = false,
}) => TechnicianJobDetail(
  job: technicianJob(status: status),
  studentName: 'Sinh viên Nguyễn An',
  studentPhone: '0901234567',
  attachments: withPhotos
      ? [
          technicianAttachment('request-photo'),
          technicianAttachment('result-photo', resultId: 'result-1'),
          technicianAttachment('feedback-photo', feedbackId: 'feedback-1'),
        ]
      : [],
  results: [
    JobResult(
      id: 'result-1',
      content: 'Đã thay ống nối dưới bồn rửa.',
      submittedAt: technicianTestDate,
      technicianName: 'Kỹ thuật viên Bình',
    ),
  ],
  feedback: [
    JobFeedback(
      id: 'feedback-1',
      kind: 'rework',
      reason: 'Nước vẫn rò ở đầu nối.',
      createdAt: technicianTestDate,
      authorName: 'Sinh viên Nguyễn An',
    ),
  ],
  history: [
    JobHistoryEntry(
      id: 'history-1',
      action: 'rework_requested',
      actorName: 'Sinh viên Nguyễn An',
      oldStatus: 'awaiting_confirmation',
      newStatus: 'awaiting_rework',
      note: 'Cần kiểm tra lại đầu nối.',
      occurredAt: technicianTestDate,
    ),
  ],
  assignments: [
    JobAssignment(
      id: 'assignment-1',
      technicianName: 'Kỹ thuật viên Bình',
      assignedByName: 'Quản lý KTX',
      assignedAt: technicianTestDate,
      endedAt: null,
      transferReason: 'Phân công theo chuyên môn nước.',
      endReason: null,
    ),
  ],
);

class TechnicianTestJobsRepository implements TechnicianJobsRepository {
  List<TechnicianJob> jobs = [technicianJob()];
  TechnicianJobDetail detail = technicianDetail();
  Future<List<TechnicianJob>> Function()? loadJobs;
  Future<TechnicianJobDetail> Function()? loadDetail;
  Future<Uint8List> Function(JobAttachment)? loadAttachment;
  int listCalls = 0;
  int detailCalls = 0;
  final attachmentCalls = <String>[];

  @override
  Future<List<TechnicianJob>> fetchJobs() async {
    listCalls++;
    return loadJobs == null ? jobs : await loadJobs!();
  }

  @override
  Future<TechnicianJobDetail> fetchJobDetail(String requestId) async {
    detailCalls++;
    return loadDetail == null ? detail : await loadDetail!();
  }

  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    JobAttachment attachment,
  ) async {
    attachmentCalls.add(attachment.id);
    return loadAttachment == null
        ? technicianPng()
        : await loadAttachment!(attachment);
  }
}

Uint8List technicianPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);
