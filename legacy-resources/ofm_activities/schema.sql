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

CREATE TABLE IF NOT EXISTS `ofm_race_results` (
  `result_id` varchar(96) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `race_id` varchar(32) NOT NULL,
  `elapsed_ms` int unsigned NOT NULL,
  `payout` int unsigned NOT NULL,
  `completed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`result_id`),
  KEY `idx_ofm_race_results_leaderboard` (`race_id`, `elapsed_ms`, `completed_at`),
  KEY `idx_ofm_race_results_citizen` (`citizenid`, `race_id`, `elapsed_ms`),
  CONSTRAINT `fk_ofm_race_results_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ofm_match_results` (
  `result_id` varchar(128) NOT NULL,
  `match_id` varchar(96) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `activity` varchar(32) NOT NULL,
  `team` varchar(16) NOT NULL,
  `kills` smallint unsigned NOT NULL DEFAULT 0,
  `deaths` smallint unsigned NOT NULL DEFAULT 0,
  `won` tinyint(1) NOT NULL DEFAULT 0,
  `payout` int unsigned NOT NULL,
  `completed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`result_id`),
  KEY `idx_ofm_match_results_match` (`match_id`, `activity`),
  KEY `idx_ofm_match_results_citizen` (`citizenid`, `activity`, `completed_at`),
  CONSTRAINT `fk_ofm_match_results_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
