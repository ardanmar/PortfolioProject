/* Cross system data quality audit:
   Return total rows and rows with data quality issues for each table
*/
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
