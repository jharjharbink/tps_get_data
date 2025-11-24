# 🧪 Test de non-régression : Import incrémental sans perte de données

## 🎯 Objectif

Vérifier que le mécanisme `START_TIME` garantit qu'**aucune donnée insérée pendant l'import incrémental n'est perdue**.

---

## 📋 Principe du mécanisme START_TIME

### Avant (problème)
```
00:00 - Début import (last_sync = 00:00)
00:01 - Import compta_00001 terminé
00:02 - ⚠️ Nouvelle écriture créée dans compta_00001 (HE_DATE_SAI = 00:02)
...
06:00 - Fin import → last_sync_date = NOW() = 06:00

PROCHAIN IMPORT :
- Filtre : WHERE HE_DATE_SAI > '06:00'
- ❌ L'écriture de 00:02 ne sera JAMAIS importée
```

### Après (solution)
```
00:00 - START_TIME = 2025-11-24 00:00:00
00:00 - Récupération LAST_SYNC = 2025-11-23 18:00:00
00:01 - Import compta_00001 (WHERE date > 18:00)
00:02 - Nouvelle écriture dans compta_00001 (HE_DATE_SAI = 00:02)
...
06:00 - Fin import → last_sync_date = START_TIME = 00:00

PROCHAIN IMPORT :
- Filtre : WHERE HE_DATE_SAI > '00:00'
- ✅ L'écriture de 00:02 sera capturée
```

---

## 🧪 Procédure de test

### Prérequis

- Base de test `compta_test` créée avec les 6 tables requises
- Import incrémental déjà effectué au moins une fois
- Accès MySQL à la source ACD et à raw_acd

---

### Étape 1 : Préparer la base de test

```sql
-- Sur le serveur ACD
USE compta_test;

-- Insérer quelques écritures de base
INSERT INTO histo_ligne_ecriture (
    HLE_CODE, HE_CODE, CPT_CODE, HLE_CRE_ORG, HLE_DEB_ORG,
    HE_DATE_SAI, HE_ANNEE, HE_MOIS, JNL_CODE
) VALUES
(1, 1, '401000', 1000.00, 0.00, '2025-11-23 12:00:00', 2025, 11, 'ACH'),
(2, 2, '411000', 0.00, 500.00, '2025-11-23 12:00:00', 2025, 11, 'VTE');
```

---

### Étape 2 : Lancer un import incrémental initial

```bash
# Noter l'heure avant de lancer
date '+%Y-%m-%d %H:%M:%S'

# Lancer l'import incrémental
bash bash/raw/02_import_raw_compta.sh --incremental

# Vérifier que les données de test sont importées
mysql -u root -p raw_acd -e "
    SELECT COUNT(*) as nb_lignes
    FROM histo_ligne_ecriture
    WHERE dossier_code = 'test'
"
# Devrait retourner : 2
```

---

### Étape 3 : Noter le START_TIME

```bash
# Vérifier le timestamp enregistré dans sync_tracking
mysql -u root -p raw_acd -e "
    SELECT
        table_name,
        last_sync_date,
        last_sync_type
    FROM sync_tracking
    WHERE table_name = 'histo_ligne_ecriture'
"
```

**Exemple de résultat** :
```
+----------------------+---------------------+----------------+
| table_name           | last_sync_date      | last_sync_type |
+----------------------+---------------------+----------------+
| histo_ligne_ecriture | 2025-11-24 10:00:00 | incremental    |
+----------------------+---------------------+----------------+
```

**👉 Noter ce timestamp : `2025-11-24 10:00:00`**

---

### Étape 4 : Lancer un nouvel import incrémental

```bash
# Lancer à 10:30 par exemple
bash bash/raw/02_import_raw_compta.sh --incremental
```

Le script devrait afficher :
```
[INFO] Timestamp de départ de l'import : 2025-11-24 10:30:00
[INFO] ⚠️  Ce timestamp sera enregistré dans sync_tracking (pas l'heure de fin)
[INFO] Récupération des dernières dates de synchronisation...
[INFO]   - histo_ligne_ecriture: 2025-11-24 10:00:00
```

---

### Étape 5 : PENDANT l'import, insérer une écriture dans compta_test

**⏰ Timing important** : Insérer l'écriture juste après que `compta_test` ait été traitée.

```sql
-- Sur le serveur ACD
USE compta_test;

-- Insérer une nouvelle écriture PENDANT l'import
-- Utiliser un timestamp ENTRE le START_TIME et NOW()
INSERT INTO histo_ligne_ecriture (
    HLE_CODE, HE_CODE, CPT_CODE, HLE_CRE_ORG, HLE_DEB_ORG,
    HE_DATE_SAI, HE_ANNEE, HE_MOIS, JNL_CODE
) VALUES
(999, 999, '512000', 2000.00, 0.00, '2025-11-24 10:35:00', 2025, 11, 'BQ');
--                                   ^^^ Entre START_TIME (10:30) et FIN (11:00) ^^^
```

**Note** : Ajuster le timestamp selon l'heure réelle de votre test.

---

### Étape 6 : Attendre la fin de l'import

```bash
# Surveiller les logs
tail -f logs/pipeline_*.log
```

Une fois terminé, vérifier le nouveau `last_sync_date` :

```sql
SELECT
    table_name,
    last_sync_date,
    last_sync_type
FROM raw_acd.sync_tracking
WHERE table_name = 'histo_ligne_ecriture';
```

**✅ Résultat attendu** :
```
+----------------------+---------------------+----------------+
| table_name           | last_sync_date      | last_sync_type |
+----------------------+---------------------+----------------+
| histo_ligne_ecriture | 2025-11-24 10:30:00 | incremental    |
+----------------------+---------------------+----------------+
```

**⚠️ Devrait afficher 10:30:00 (START_TIME) et PAS 11:00 (heure de fin)**

---

### Étape 7 : Vérifier que l'écriture insérée N'EST PAS encore importée

```sql
SELECT COUNT(*) as nb_lignes
FROM raw_acd.histo_ligne_ecriture
WHERE dossier_code = 'test'
AND HLE_CODE = 999;
```

**✅ Résultat attendu** : `0` (l'écriture n'est pas encore importée)

**Raison** : L'écriture a été créée à `10:35` (après le START_TIME de `10:30`), mais après que `compta_test` ait été traitée.

---

### Étape 8 : Lancer un NOUVEAU import incrémental

```bash
# Lancer à 12:00 par exemple
bash bash/raw/02_import_raw_compta.sh --incremental
```

Le script devrait utiliser `last_sync_date = 2025-11-24 10:30:00` pour filtrer les données.

---

### Étape 9 : Vérifier que l'écriture a bien été importée

```sql
SELECT COUNT(*) as nb_lignes
FROM raw_acd.histo_ligne_ecriture
WHERE dossier_code = 'test'
AND HLE_CODE = 999;
```

**✅ Résultat attendu** : `1`

**Vérifier les détails** :
```sql
SELECT
    dossier_code,
    HLE_CODE,
    HE_CODE,
    CPT_CODE,
    HLE_CRE_ORG,
    HE_DATE_SAI
FROM raw_acd.histo_ligne_ecriture
WHERE dossier_code = 'test'
AND HLE_CODE = 999;
```

**✅ Résultat attendu** :
```
+--------------+----------+---------+---------+-------------+---------------------+
| dossier_code | HLE_CODE | HE_CODE | CPT_CODE | HLE_CRE_ORG | HE_DATE_SAI         |
+--------------+----------+---------+---------+-------------+---------------------+
| test         |      999 |     999 | 512000  |     2000.00 | 2025-11-24 10:35:00 |
+--------------+----------+---------+---------+-------------+---------------------+
```

---

## ✅ Critères de succès

| Critère | Statut attendu |
|---------|----------------|
| `last_sync_date` = START_TIME (pas heure de fin) | ✅ |
| Écriture insérée pendant import N'est PAS dans raw_acd après 1er import | ✅ |
| Écriture insérée pendant import EST dans raw_acd après 2ème import | ✅ |
| Aucun doublon créé (vérifier avec clé primaire) | ✅ |
| Logs affichent "Timestamp de départ de l'import" | ✅ |

---

## 🔍 Vérifications supplémentaires

### Vérifier l'absence de doublons

```sql
SELECT
    dossier_code,
    HLE_CODE,
    HE_ANNEE,
    COUNT(*) as nb_doublons
FROM raw_acd.histo_ligne_ecriture
WHERE dossier_code = 'test'
GROUP BY dossier_code, HLE_CODE, HE_ANNEE
HAVING COUNT(*) > 1;
```

**✅ Résultat attendu** : Aucune ligne (pas de doublons)

---

### Vérifier que toutes les écritures sont importées

```sql
-- Sur le serveur ACD
SELECT COUNT(*) FROM compta_test.histo_ligne_ecriture;

-- Sur raw_acd
SELECT COUNT(*) FROM raw_acd.histo_ligne_ecriture WHERE dossier_code = 'test';
```

**✅ Les deux requêtes doivent retourner le même nombre**

---

## 📊 Analyse des cas limites

### Cas 1 : Import échoue à mi-parcours

**Scénario** :
- START_TIME = 10:00
- Import plante à 12:00
- `last_sync_date` N'EST PAS mis à jour

**Résultat attendu** :
- Prochain import repartira depuis le dernier `last_sync_date` réussi
- Bases déjà traitées seront réimportées (doublons gérés par clés primaires)
- ✅ Aucune perte de données

---

### Cas 2 : Écritures avec date future

**Scénario** :
```sql
INSERT INTO compta_test.histo_ligne_ecriture (...)
VALUES (..., HE_DATE_SAI = '2026-01-01 00:00:00', ...);
```

**Résultat attendu** :
- Filtre `WHERE HE_DATE_SAI > last_sync_date` capturera ces écritures
- ✅ Pas de problème

---

### Cas 3 : Écriture modifiée (pas nouvelle)

**Scénario** :
```sql
-- Écriture existante dans raw_acd
UPDATE compta_test.histo_ligne_ecriture
SET HLE_CRE_ORG = 9999.99
WHERE HLE_CODE = 1;
```

**Résultat attendu** :
- ❌ Le champ `HE_DATE_SAI` ne change pas → pas réimportée
- **Solution** : Import `--full` hebdomadaire pour recapture
- **Alternative future** : Utiliser `HE_DATE_MODIF` si disponible dans ACD

---

## 🎯 Recommandations

1. **Exécuter ce test sur 10 bases** avant de lancer en prod sur 3500 bases
2. **Automatiser ce test** dans un script de CI/CD
3. **Planifier un import `--full` hebdomadaire** pour capturer les modifications

---

## 📞 Support

En cas d'échec du test :
1. Vérifier les logs : `logs/pipeline_*.log`
2. Vérifier `sync_tracking` : `SELECT * FROM raw_acd.sync_tracking;`
3. Vérifier les clés primaires : `SHOW CREATE TABLE raw_acd.histo_ligne_ecriture;`

---

**Date de création** : 2025-11-24
**Version du script** : 02_import_raw_compta.sh avec mécanisme START_TIME
