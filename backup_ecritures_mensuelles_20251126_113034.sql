/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.11.14-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: transform_compta
-- ------------------------------------------------------
-- Server version	10.11.14-MariaDB-0+deb12u2

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `ecritures_mensuelles`
--

DROP TABLE IF EXISTS `ecritures_mensuelles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ecritures_mensuelles` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `source` enum('ACD','PENNYLANE') NOT NULL,
  `code_dossier` varchar(64) NOT NULL COMMENT 'Code_DIA pour ACD, name pour Pennylane',
  `siren` varchar(9) DEFAULT NULL COMMENT 'Pour jointure MDM',
  `period_month` date NOT NULL COMMENT 'Premier jour du mois',
  `compte` varchar(64) NOT NULL COMMENT 'Comptes C*/F* agrégés en Cxxxxx/Fxxxxx',
  `compte_libelle` varchar(255) DEFAULT NULL,
  `journal_code` varchar(32) NOT NULL DEFAULT '',
  `journal_libelle` varchar(255) DEFAULT NULL,
  `debits` decimal(18,2) NOT NULL DEFAULT 0.00,
  `credits` decimal(18,2) NOT NULL DEFAULT 0.00,
  `solde` decimal(18,2) GENERATED ALWAYS AS (`debits` - `credits`) STORED,
  `nb_ecritures` int(11) NOT NULL DEFAULT 0,
  `date_derniere_saisie` datetime DEFAULT NULL,
  `synchro_date` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ecriture` (`source`,`code_dossier`,`period_month`,`compte`,`journal_code`),
  KEY `idx_source` (`source`),
  KEY `idx_dossier` (`code_dossier`),
  KEY `idx_siren` (`siren`),
  KEY `idx_period` (`period_month`),
  KEY `idx_compte` (`compte`),
  KEY `idx_journal` (`journal_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ecritures_mensuelles`
--

LOCK TABLES `ecritures_mensuelles` WRITE;
/*!40000 ALTER TABLE `ecritures_mensuelles` DISABLE KEYS */;
/*!40000 ALTER TABLE `ecritures_mensuelles` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-11-26 11:30:34
