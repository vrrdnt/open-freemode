CREATE TABLE IF NOT EXISTS `ofm_property_purchases` (
  `purchase_id` varchar(96) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `property_id` varchar(50) NOT NULL,
  `price` int unsigned NOT NULL,
  `purchased_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`citizenid`, `property_id`),
  UNIQUE KEY `uq_ofm_property_purchase_request` (`purchase_id`),
  KEY `idx_ofm_property_purchases_time` (`citizenid`, `purchased_at`),
  CONSTRAINT `fk_ofm_property_purchase_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
