/* Data quality audit & format profiling */
-- Return total rows and rows with data quality issues for each source table
SELECT
  'pelanggan_legacy' AS sumber,
  COUNT(*) AS total_baris,
  SUM(
    CASE 
    WHEN email IS NULL
      OR kota IS NULL
      OR kategori IS NULL
      THEN 1
    ELSE 0
    END
  ) AS masalah_utama
FROM pelanggan_legacy
UNION ALL
SELECT
  'pelanggan_akuisisi' AS sumber,
  COUNT(*) AS total_baris,
  SUM(
    CASE 
      WHEN email IS NULL
        OR tipe_pelanggan IS NULL
        THEN 1
      ELSE 0
    END
  ) AS masalah_utama
FROM pelanggan_akuisisi
UNION ALL
SELECT
  'pelanggan_modern' AS sumber,
  COUNT(*) AS total_baris,
  COUNT(*) FILTER(
    WHERE alamat IS NULL
      OR email IS NULL
  ) AS masalah_utama
FROM pelanggan_modern
UNION ALL
SELECT
  'transaksi' AS sumber,
  COUNT(*) AS total_baris,
  COUNT(*) FILTER(
    WHERE total <= 0
      OR status NOT IN ('selesai', 'pending', 'batal')
  )
FROM transaksi
ORDER BY sumber;

-- Return phone number format variation from pelanggan_legacy
SELECT
  CASE
      WHEN telepon LIKE '+62%' THEN '+62'
      WHEN telepon LIKE '08%' 
        AND telepon LIKE '%-%'
        THEN '08 dengan dash'
      WHEN telepon LIKE '08%' THEN '08 plain'
      WHEN telepon LIKE '021%' THEN '021 fixed line'
      WHEN telepon LIKE '8%' THEN 'tanpa leading 0'
      ELSE 'lainnya'
  END AS pola_telepon,
  COUNT(*) AS jumlah
FROM pelanggan_legacy
GROUP BY pola_telepon
ORDER BY jumlah DESC;

/* Cleaning Pipeline Query */
-- Standardize 'tgl_daftar' format and retain only digit from 'telepon' in pelanggan_legacy
WITH legacy_normalized AS (
  SELECT
    id,
    nama,
    email,
    REGEXP_REPLACE(telepon, '[^0-9]', '', 'g') AS telepon_digit,
    kota,
    kategori,
    CASE
      WHEN tgl_daftar LIKE '__/__/____' THEN CAST(STRPTIME(tgl_daftar, '%d/%m/%Y') AS DATE)
      ELSE CAST(tgl_daftar AS DATE)
    END AS tgl_daftar_dt
  FROM pelanggan_legacy
  WHERE email IS NOT NULL
),
   
-- Standardize text, normalize 'telepon', and handle null value in legacy_normalized
legacy_clean AS (
  SELECT
    id,
    LOWER(TRIM(email)) AS email,    
    LOWER(TRIM(nama)) AS nama,
    CASE
        WHEN telepon_digit LIKE '62%' THEN '08' || SUBSTRING(telepon_digit, 3)
        WHEN telepon_digit LIKE '8%' THEN '0' || telepon_digit
        ELSE telepon_digit
    END AS telepon,
    COALESCE(LOWER(TRIM(kota)), 'tidak diketahui') AS kota,
    COALESCE(LOWER(TRIM(kategori)), 'reguler') AS kategori,
    'legacy' AS sumber_kanonik,
    tgl_daftar_dt AS tgl_daftar
  FROM legacy_normalized
),

-- Standardize text fields and date format in pelanggan_akuisisi
akuisisi_clean AS (
  SELECT
    id,
    LOWER(TRIM(email)) AS email,
    LOWER(TRIM(nama_lengkap)) AS nama,
    LOWER(TRIM(nomor_hp)) AS telepon,
    LOWER(TRIM(kota)) AS kota,
    LOWER(TRIM(tipe_pelanggan)) AS kategori,
    'akuisisi' AS sumber_kanonik,
    CAST(tanggal_registrasi AS DATE) AS tgl_daftar
  FROM pelanggan_akuisisi
  WHERE email IS NOT NULL
),

-- Standarize text fields and date format in pelanggan_modern
modern_legacy AS (
  SELECT
    id,
    LOWER(TRIM(email)) AS email,
    LOWER(TRIM(nama)) AS nama,
    LOWER(TRIM(telepon)) AS telepon,
    LOWER(TRIM(kota)) AS kota,
    LOWER(TRIM(kategori)) AS kategori,
    'modern' AS sumber_kanonik,
    CASE
        WHEN tgl_daftar LIKE '__/__/____' THEN CAST(STRPTIME(tgl_daftar, '%d/%m/%Y') AS DATE)
        ELSE CAST(tgl_daftar AS DATE)
    END tgl_daftar
  FROM pelanggan_modern
),

-- Combine all cleaned customer tables into unified dataset
unified AS (
  SELECT
    *
  FROM legacy_clean
  UNION ALL
  SELECT
    *
  FROM akuisisi_clean
  UNION ALL
  SELECT
    *
  FROM modern_legacy
),

-- Deduplicate combined records by email, prioritizing the earliest 'tgl_daftar'
deduped AS (
  SELECT
    *,
    ROW_NUMBER(*) OVER(
      PARTITION BY email
      ORDER BY tgl_daftar
    ) rn
  FROM unified
),

pelanggan_final AS (
  SELECT
    email,
    nama,
    telepon,
    kota,
    kategori,
    sumber_kanonik
  FROM deduped
  WHERE rn = 1
),

-- Standardize 'status' values and validate transaction records by filtering based on specified conditions
transaksi_clean AS (  
  SELECT
    id,
    pelanggan_id,
    sumber_sistem,
    tanggal,
    total,
    CASE status
        WHEN 'selesai' THEN 'selesai'
        WHEN 'batal' THEN 'batal'
        WHEN 'pending' THEN 'pending'
        WHEN 'completed' THEN 'selesai'
        WHEN 'cancelled' THEN 'batal'
        ELSE NULL
    END status
  FROM transaksi
  WHERE total > 0
    AND status IS NOT NULL
),

-- Filter out orphan transactions without matching customers
transaksi_valid AS (
SELECT
  u.email,
  tc.*
FROM transaksi_clean AS tc 
JOIN unified AS u
    ON u.id = tc.pelanggan_id
)

-- Return customer information with transaction count and total spending
SELECT
  p.email,
  p.nama,
  p.kota,
  p.kategori,
  p.sumber_kanonik,
  COUNT(t.id) AS jumlah_transaksi,
  COALESCE(SUM(t.total), 0) AS total_belanja
FROM pelanggan_final AS p
LEFT JOIN transaksi_valid AS t 
  ON p.email = t.email
GROUP BY
  p.email,
  p.nama,
  p.kota,
  p.kategori,
  p.sumber_kanonik  
ORDER BY total_belanja DESC;
