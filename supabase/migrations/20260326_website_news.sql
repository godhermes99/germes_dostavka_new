-- Таблица для новостей и акций на сайте
CREATE TABLE IF NOT EXISTS website_news (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT NOT NULL DEFAULT 'news' CHECK (type IN ('news', 'promo')),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  emoji TEXT DEFAULT '📰',
  color_from TEXT DEFAULT '#005BBB',
  color_to TEXT DEFAULT '#0077FF',
  promo_code TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: читать могут все, редактировать — только авторизованные (админ)
ALTER TABLE website_news ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read" ON website_news
  FOR SELECT USING (true);

CREATE POLICY "Admin insert" ON website_news
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Admin update" ON website_news
  FOR UPDATE USING (true);

CREATE POLICY "Admin delete" ON website_news
  FOR DELETE USING (true);
