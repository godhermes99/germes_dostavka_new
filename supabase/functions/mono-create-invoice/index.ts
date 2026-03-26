import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Обробка CORS для запитів з Flutter
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { order_id, prep_time_minutes, restaurant_comment, new_total_amount } = await req.json()

    const monoToken = Deno.env.get('MONOBANK_TOKEN')
    if (!monoToken) throw new Error('Токен Monobank не налаштовано')

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey)

    // 1. Отримуємо дані замовлення з бази
    const { data: order, error: fetchError } = await supabaseAdmin
      .from('orders')
      .select('*')
      .eq('id', order_id)
      .single()

    if (fetchError || !order) throw new Error('Замовлення не знайдено')

    // 2. Якщо ресторан змінив суму (наприклад, видалив страву), беремо нову суму, інакше беремо стару
    const finalAmount = new_total_amount ? parseFloat(new_total_amount) : order.total_amount
    const amountInKopecks = Math.round(finalAmount * 100) // Монобанк приймає суму в копійках

    // 3. Формуємо запит до Монобанку для створення рахунку
    const monoReqBody = {
      amount: amountInKopecks,
      ccy: 980, // Код гривні UAH
      merchantPaymInfo: {
        reference: order_id.toString(),
        destination: `Оплата замовлення №${order_id.toString().substring(0, 5)}`,
      },
      // ВАЖЛИВО: Монобанк буде слати сюди вебхук про статус оплати!
      webHookUrl: `${supabaseUrl}/functions/v1/mono-webhook`
    }

    const monoResponse = await fetch('https://api.monobank.ua/api/merchant/invoice/create', {
      method: 'POST',
      headers: {
        'X-Token': monoToken,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(monoReqBody)
    })

    const monoData = await monoResponse.json()

    if (!monoResponse.ok) {
      throw new Error(monoData.errText || 'Помилка створення рахунку в Монобанку')
    }

    const invoiceId = monoData.invoiceId

    // 4. Оновлюємо базу даних: записуємо рахунок, час, коментар і міняємо статус!
    const { error: updateError } = await supabaseAdmin
      .from('orders')
      .update({
        status: 'Очікує оплати', // Це запустить тихий пуш клієнту!
        payment_id: invoiceId,   // Зберігаємо рахунок
        prep_time_minutes: prep_time_minutes,
        restaurant_comment: restaurant_comment,
        total_amount: finalAmount
      })
      .eq('id', order_id)

    if (updateError) throw updateError

    return new Response(JSON.stringify({ success: true, invoiceId }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Error creating invoice:', error.message)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})