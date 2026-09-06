CREATE TABLE IF NOT EXISTS `ofm_activity_results` (
  `result_id` varchar(96) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `activity` varchar(32) NOT NULL,
  `payout` int unsigned NOT NULL,
  `completed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`result_id`),
  KEY `idx_ofm_activity_results_citizen` (`citizenid`, `completed_at`),
  CONSTRAINT `fk_ofm_activity_results_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
