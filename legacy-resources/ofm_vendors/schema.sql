CREATE TABLE IF NOT EXISTS `ofm_vendor_purchases` (
  `purchase_id` varchar(96) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `vendor_id` varchar(50) NOT NULL,
  `item_name` varchar(50) NOT NULL,
  `price` int unsigned NOT NULL,
  `purchased_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`purchase_id`),
  KEY `idx_ofm_vendor_purchases_character` (`citizenid`, `purchased_at`),
  CONSTRAINT `fk_ofm_vendor_purchase_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
