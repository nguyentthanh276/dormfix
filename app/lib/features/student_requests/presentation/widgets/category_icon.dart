import 'package:flutter/material.dart';

/// Biểu tượng theo tên loại sự cố; tên lạ thì dùng biểu tượng "Khác".
IconData categoryIcon(String name) => switch (name) {
  'Điện' => Icons.electrical_services,
  'Nước' => Icons.water_drop_outlined,
  'Nội thất' => Icons.chair_outlined,
  _ => Icons.more_horiz,
};
