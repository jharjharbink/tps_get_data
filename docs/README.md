# 📊 Architecture Data - Phase 1
## Pipeline 4 couches : RAW → TRANSFORM → MDM → MART

---

## 🎯 Vue d'ensemble

Cette architecture unifie les données comptables provenant de :
- **ACD/DIA** : Bases `compta_*` + `valoxy` (DIA)
- **Pennylane** : Données exportées depuis Redshift

### Architecture des couches

```
┌─────────────────────────────────────────────────────────────────────┐
│                           SOURCES                                    │
├──────────────┬──────────────┬──────────────┬───────────────────────┤
│   DIA        │   compta_*   │  Pennylane   │  (Futures: Silae,     │
│  (valoxy)    │    (ACD)     │  (Redshift)  │   Tiime, PolyActe...) │
└──────┬───────┴──────┬───────┴──────┬───────┴───────────────────────┘
       │              │              │
       ▼              ▼              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        COUCHE RAW                                    │
│  Copies brutes, pas de transformation                                │
├──────────────┬──────────────┬──────────────────────────────────────┤
│   raw_dia    │   compta_*   │   raw_pennylane                       │
│              │  (inchangé)  │   pl_*, acc_*, etl_*, pm_*            │
└──────┬───────┴──────┬───────┴──────┬───────────────────────────────┘
       │              │              │
       └──────────────┼──────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     COUCHE TRANSFORM                                 │
│  Nettoyage, normalisation, agrégation                               │
├─────────────────────────────────────────────────────────────────────┤
│   transform_compta                                                   │
│   - dossiers_acd, dossiers_pennylane                                │
│   - ecritures_mensuelles (C*/F* agrégés)                            │
│   - ecritures_tiers_detaillees (C*/F* détaillés, normalisés 401/411)│
│   - exercices, temps_collaborateurs                                  │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        COUCHE MDM                                    │
│  Référentiel maître - Jointure sur SIREN                            │
├─────────────────────────────────────────────────────────────────────┤
│   mdm                                                                │
│   - dossiers (unifié ACD ↔ Pennylane)                               │
│   - collaborateurs                                                   │
│   - contacts                                                         │
│   - mapping_comptes_services                                         │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        COUCHE MART                                   │
│  Vues métier pour reporting                                         │
├──────────────────┬──────────────────┬───────────────────────────────┤
│ mart_pilotage_   │ mart_controle_   │ mart_production_              │
│ cabinet          │ gestion          │ client                        │
├──────────────────┼──────────────────┼───────────────────────────────┤
│ v_clients_par_   │ v_company_ledger │ v_tiers_detailles             │
│   service        │ v_tableau_bord_  │ v_tiers_agrege                │
│ v_penetration_   │   global         │ v_evolution_ca                │
│   services       │ v_temps_par_     │ v_top_clients_                │
│ v_portefeuille_  │   dossier        │   fournisseurs                │
│   collaborateur  │ v_temps_par_     │                               │
│ v_entrees_       │   collaborateur  │                               │
│   sorties        │ v_exercices      │                               │
│ v_repartition_   │                  │                               │
│   entites        │                  │                               │
└──────────────────┴──────────────────┴───────────────────────────────┘
```

---

## 📁 Structure des fichiers

```
projet_test/
├── run_pipeline.sh              # 🚀 Script principal (tout en un)
├── bash/
│   ├── config.sh                # Configuration (à adapter!)
│   ├── logging.sh               # Fonctions de log
│   ├── raw/
│   │   ├── 01_import_raw_dia.sh
│   │   ├── 02_import_raw_compta.sh
│   │   ├── 03_import_raw_pennylane.sh
│   │   └── run_all_raw.sh
│   ├── transform/
│   │   └── run_transform.sh
│   ├── mdm/
│   │   └── run_mdm.sh
│   └── mart/
│       └── run_mart.sh
├── sql/
│   ├── 01_create_schemas.sql
│   ├── 02_raw_pennylane_tables.sql
│   ├── 03_transform_tables.sql
│   ├── 04_mdm_tables.sql
│   ├── 05_mart_views.sql
│   ├── 06_procedures_transform_part1.sql
│   ├── 06_procedures_transform_part2.sql
│   ├── 07_procedures_mdm.sql
│   └── 08_procedures_orchestrator.sql
└── docs/
    └── README.md (ce fichier)
```

---

## 🚀 Utilisation

### 1. Configuration

Éditer `bash/config.sh` avec vos paramètres :

```bash
# Mots de passe à remplacer
export LOCAL_PASS="votre_mot_de_passe"
export DIA_PASS="votre_mot_de_passe"
export ACD_PASS="votre_mot_de_passe"
# etc.
```

### 2. Exécution complète

```bash
# Pipeline complet (RAW → TRANSFORM → MDM → MART)
./run_pipeline.sh

# Sans réimport des données RAW (plus rapide pour les tests)
./run_pipeline.sh --skip-raw

# Seulement TRANSFORM (après modification des procédures)
./run_pipeline.sh --transform-only

# Seulement MDM
./run_pipeline.sh --mdm-only
```

### 3. Exécution par couche

```bash
# Imports RAW uniquement
bash bash/raw/run_all_raw.sh

# TRANSFORM uniquement
bash bash/transform/run_transform.sh

# MDM uniquement
bash bash/mdm/run_mdm.sh

# MART uniquement
bash bash/mart/run_mart.sh
```

### 4. Exécution des procédures individuelles

```bash
# Depuis MySQL
CALL transform_compta.load_dossiers_acd();
CALL transform_compta.load_ecritures_acd();
CALL mdm.load_dossiers();
# etc.
```

---

## 📊 Tables et vues principales

### TRANSFORM

| Table | Description | Volume estimé |
|-------|-------------|---------------|
| `dossiers_acd` | Dossiers DIA normalisés | ~3,500 |
| `dossiers_pennylane` | Dossiers Pennylane normalisés | ~1,000 |
| `ecritures_mensuelles` | Balance mensuelle (C/F agrégés) | ~4M |
| `ecritures_tiers_detaillees` | Détail 401/411 normalisés | ~8M |
| `exercices` | Exercices comptables unifiés | ~20,000 |
| `temps_collaborateurs` | Temps passés | ~250,000 |

### MDM

| Table | Description | Clé de jointure |
|-------|-------------|-----------------|
| `dossiers` | Référentiel unifié | SIREN |
| `collaborateurs` | Référentiel collabs | COL_CODE |
| `contacts` | Contacts des dossiers | COR_ID |

### MART

| Schéma | Vue | Usage |
|--------|-----|-------|
| `mart_pilotage_cabinet` | `v_clients_par_service` | Matrice clients × services |
| `mart_pilotage_cabinet` | `v_penetration_services` | Multi-équipement |
| `mart_controle_gestion` | `v_company_ledger` | Balance unifiée Power BI |
| `mart_controle_gestion` | `v_temps_par_dossier` | Analyse temps |
| `mart_production_client` | `v_tiers_detailles` | Détail 401/411 |
| `mart_production_client` | `v_evolution_ca` | Évolution CA |

---

## 🔄 Mapping des comptes

### ACD → Normalisation

| Compte ACD | Compte normalisé | Type |
|------------|------------------|------|
| `C*` (ex: C00123) | `411` | Client |
| `F*` (ex: F00456) | `401` | Fournisseur |
| Autres | Inchangés | - |

### ecritures_mensuelles vs ecritures_tiers_detaillees

- **ecritures_mensuelles** : Comptes C*/F* agrégés en `Cxxxxx`/`Fxxxxx` (comme ta table `comptes_row_flux`)
- **ecritures_tiers_detaillees** : Comptes C*/F* détaillés avec normalisation 401/411 (comme ta table `comptes_row_flux_fournisseur_client`)

---

## 🔗 Jointure MDM

La jointure ACD ↔ Pennylane se fait sur **SIREN** :

```sql
-- ACD : LEFT(ADR_SIRET, 9)
-- Pennylane : LEFT(registration_number, 9)

SELECT 
    d.siren,
    d.code_dia,          -- Code DIA (ACD)
    d.company_id_pennylane,  -- ID Pennylane
    d.has_compta_acd,
    d.has_compta_pennylane
FROM mdm.dossiers d;
```

---

## 📅 Planification recommandée

| Fréquence | Couche | Script |
|-----------|--------|--------|
| Quotidien | RAW (DIA) | `01_import_raw_dia.sh` |
| Quotidien | TRANSFORM | `run_transform.sh` |
| Quotidien | MDM | `run_mdm.sh` |
| Hebdomadaire | RAW (compta_*) | `02_import_raw_compta.sh` |
| Hebdomadaire | RAW (Pennylane) | `03_import_raw_pennylane.sh` |

Exemple crontab :

```cron
# Quotidien à 2h00 : DIA + TRANSFORM + MDM
0 2 * * * /home/valoxy/scripts/run_pipeline.sh --skip-raw 2>&1 | logger -t data-pipeline

# Dimanche à 1h00 : Import complet
0 1 * * 0 /home/valoxy/scripts/run_pipeline.sh 2>&1 | logger -t data-pipeline
```

---

## 🔮 Roadmap Phase 2+

- [ ] Sources additionnelles : Tiime, Silae, OpenPaye, PolyActe, RevisAudit
- [ ] Détection automatique des services depuis comptabilité interne
- [ ] Synchronisation incrémentale (ETL avec deleted_at/synchronised_at)
- [ ] Alertes sur qualité des données
- [ ] API REST pour accès aux données MDM

---

## 🛠️ Dépannage

### Erreur de connexion MySQL distant

```bash
# Tester la connexion
mysql -h 192.168.20.24 -P 3306 -u root -p -e "SELECT 1"
```

### Procédure qui échoue

```sql
-- Voir les erreurs détaillées
CALL transform_compta.load_ecritures_acd();
-- Le handler affiche le détail de l'erreur
```

### Vérifier les volumes

```sql
SELECT 
    table_schema,
    table_name,
    table_rows,
    ROUND(data_length / 1024 / 1024, 2) AS size_mb
FROM information_schema.tables
WHERE table_schema IN ('transform_compta', 'mdm', 'raw_pennylane')
ORDER BY table_schema, table_name;
```

---

## 📞 Support

Pour toute question sur cette architecture, contacter l'équipe IT Valoxy.
