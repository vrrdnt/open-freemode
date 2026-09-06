CREATE TABLE IF NOT EXISTS `ofm_vehicle_purchases` (
  `purchase_id` varchar(96) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `vehicle_id` int(11) NOT NULL,
  `model` varchar(50) NOT NULL,
  `price` int unsigned NOT NULL,
  `purchased_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`purchase_id`),
  UNIQUE KEY `uq_ofm_vehicle_purchases_vehicle` (`vehicle_id`),
  KEY `idx_ofm_vehicle_purchases_citizen` (`citizenid`, `purchased_at`),
  CONSTRAINT `fk_ofm_vehicle_purchase_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE,
  CONSTRAINT `fk_ofm_vehicle_purchase_vehicle` FOREIGN KEY (`vehicle_id`) REFERENCES `player_vehicles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
