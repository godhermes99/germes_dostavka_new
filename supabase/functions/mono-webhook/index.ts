import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1'

serve(async (req) => {
  try {
    const body = await req.json()
    console.log("🔥 MONO WEBHOOK BODY:", JSON.stringify(body, null, 2))

    const { reference, status, invoiceId } = body

    if (!reference) return new Response('OK', { status: 200 })

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 🔥 ВИПРАВЛЕНО: Реагуємо ТІЛЬКИ на реальні гроші (success або hold)
    if (status === 'success' || status === 'hold') {

      const { error } = await supabaseAdmin
        .from('orders')
        .update({
          status: 'Готується', // Одразу відправляємо на кухню!
          payment_id: invoiceId
        })
        .eq('id', reference)

      if (error) {
        console.error('❌ Помилка оновлення бази:', error)
        throw error
      } else {
        console.log(`✅ Замовлення ${reference} оплачено! Статус змінено на "Готується"`)
      }
    }
    // 🔥 НОВИЙ БЛОК: Клієнт просто відкрив сторінку (нічого не робимо)
    else if (status === 'processing') {
      console.log(`⏳ Клієнт вводить дані картки для замовлення ${reference}. Чекаємо...`)
    }
    else if (status === 'failure') {
      console.log(`⚠️ Оплата не пройшла для ${reference}. Даємо клієнту шанс переоплатити.`)
    }

    return new Response('OK', { status: 200 })

  } catch (error) {
    console.error('❌ Webhook error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})