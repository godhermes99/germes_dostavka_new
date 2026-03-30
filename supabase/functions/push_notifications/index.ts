import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { GoogleAuth } from 'npm:google-auth-library@8'

serve(async (req) => {
  try {
    const payload = await req.json()
    const record = payload.record
    const oldRecord = payload.old_record

    if (!record || !record.status) return new Response('OK', { status: 200 })
    if (oldRecord && record.status === oldRecord.status) return new Response('OK', { status: 200 })

    const status = record.status;
    const shortId = record.id.toString().substring(0, 5);

    console.log(`💡 Статус змінився на: [${status}]`);

    const messagesToSend = [];

    // 1. РЕСТОРАН: Нове замовлення
    if (status === 'Очікує підтвердження') {
      messagesToSend.push({
        topic: `restaurant_${record.restaurant_id}`,
        title: '🔔 Нове замовлення!',
        body: `Замовлення #${shortId}. Вкажіть час приготування.`
      });
    }
    // 2. КЛІЄНТ: Ресторан вказав час, треба оплатити
    else if (status === 'Очікує оплати') {
      messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '💳 Час оплатити замовлення!',
        body: 'Ресторан підтвердив замовлення. Сплатіть рахунок.'
      });
    }
    // 3. УСПІШНА ОПЛАТА (Пуш клієнту, ресторану ТА КУР'ЄРУ)
    else if (status === 'Готується' || status === 'Нове (Сплачено)') {
      messagesToSend.push({
        topic: `restaurant_${record.restaurant_id}`,
        title: '✅ ОПЛАЧЕНО!',
        body: `Замовлення #${shortId} успішно оплачено. Починайте готувати!`
      });
      messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '👨‍🍳 Кухня прийняла замовлення!',
        body: 'Оплату отримано. Ваші страви вже почали готувати.'
      });

<<<<<<< HEAD
      // 🔥 НОВЕ: КЛИЧЕМО КУР'ЄРА!
      const prepTime = record.prep_time_minutes ? record.prep_time_minutes : 'декілька';
      if (!record.courier_id) {
        // Якщо кур'єра ще немає - кидаємо в загальний пул
        messagesToSend.push({
          topic: `couriers`, // Усі кур'єри мають бути підписані на цей топік
=======
      // Кличемо кур'єра
      const prepTime = record.prep_time_minutes ? record.prep_time_minutes : 'декілька';
      if (!record.courier_id) {
        messagesToSend.push({
          topic: `couriers`,
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
          title: '🛵 З\'явилося нове замовлення!',
          body: `Ресторан почав готувати. Буде готово через ${prepTime} хв. Хто забере?`
        });
      } else {
<<<<<<< HEAD
        // Якщо кур'єр вже закріплений
=======
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
        messagesToSend.push({
          topic: `courier_${record.courier_id}`,
          title: '🛵 Кухня почала готувати!',
          body: `Замовлення #${shortId} буде готово через ${prepTime} хв. Прямуйте до ресторану.`
        });
      }
    }
    // 4. КЛІЄНТ ТА КУР'ЄР: Готово до видачі
    else if (status === 'Готово до видачі') {
       messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '🛍️ Замовлення зібрано!',
        body: 'Ваше замовлення чекає в ресторані.'
      });
<<<<<<< HEAD
      // Нагадуємо кур'єру, що вже час забирати
=======
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
      if (record.courier_id) {
        messagesToSend.push({
          topic: `courier_${record.courier_id}`,
          title: '🛍️ Пакет чекає на вас!',
          body: `Замовлення #${shortId} зібрано. Забирайте на барі.`
        });
      }
    }
    // 5. КЛІЄНТ: В дорозі
    else if (status === 'В дорозі') {
      messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '🛵 Кур\'єр в дорозі!',
        body: 'Ваше замовлення вже мчить до вас.'
      });
    }
    // 6. КЛІЄНТ: Доставлено
    else if (status === 'Доставлено') {
      messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '✅ Смачного!',
        body: 'Замовлення успішно доставлено. Дякуємо, що ви з нами!'
      });
    }
<<<<<<< HEAD
    // 7. СКАСУВАННЯ
    else if (status === 'Відхилено' || status === 'Скасовано') {
      messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '❌ Замовлення скасовано',
        body: record.cancellation_reason ? `Причина: ${record.cancellation_reason}` : 'На жаль, замовлення було скасовано.'
      });
      messagesToSend.push({
        topic: `restaurant_${record.restaurant_id}`,
        title: '❌ Клієнт відмовився!',
        body: `Клієнт скасував або не оплатив замовлення #${shortId}.`
=======
    // 7. ВІДХИЛЕНО РЕСТОРАНОМ
    else if (status === 'Відхилено') {
      messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '❌ Ресторан відхилив замовлення',
        body: record.cancellation_reason ? `Причина: ${record.cancellation_reason}` : 'На жаль, заклад не може виконати замовлення.'
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
      });
      // Повідомляємо кур'єра, щоб не їхав дарма
      if (record.courier_id) {
         messagesToSend.push({
          topic: `courier_${record.courier_id}`,
          title: '❌ Відбій!',
<<<<<<< HEAD
          body: `Замовлення #${shortId} було скасовано.`
=======
          body: `Замовлення #${shortId} було скасовано рестораном.`
        });
      }
      // 🛑 Ресторану пуш НЕ шлемо, бо він сам натиснув кнопку "Відхилити"
    }
    // 8. СКАСОВАНО КЛІЄНТОМ
    else if (status === 'Скасовано') {
      messagesToSend.push({
        topic: `client_${record.user_id}`,
        title: '❌ Замовлення скасовано',
        body: 'Ваше замовлення успішно скасовано.'
      });
      messagesToSend.push({
        topic: `restaurant_${record.restaurant_id}`,
        title: '❌ Клієнт скасував замовлення!',
        body: record.cancellation_reason ? `Причина: ${record.cancellation_reason}` : `Клієнт відмовився від замовлення #${shortId}.`
      });
      // Повідомляємо кур'єра
      if (record.courier_id) {
         messagesToSend.push({
          topic: `courier_${record.courier_id}`,
          title: '❌ Відбій!',
          body: `Клієнт скасував замовлення #${shortId}.`
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
        });
      }
    }

    if (messagesToSend.length === 0) {
        return new Response('OK', { status: 200 });
    }

    const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!serviceAccountStr) throw new Error("Секрет FIREBASE_SERVICE_ACCOUNT не знайдено!");
    const serviceAccount = JSON.parse(serviceAccountStr);

    const auth = new GoogleAuth({
      credentials: {
        client_email: serviceAccount.client_email,
        private_key: serviceAccount.private_key.replace(/\\n/g, '\n'),
      },
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });

    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    for (const msg of messagesToSend) {
        const isRestaurant = msg.topic.startsWith('restaurant_');
        const isCourier = msg.topic.startsWith('courier');

        const androidSound = isRestaurant ? "loud_alarm" : "default";
        const iosSound = isRestaurant ? "loud_alarm.mp3" : "default";
        const androidChannelId = isRestaurant ? "hermes_loud_channel" : "order_status_channel_v2";

        // Для кур'єрів і ресторанів ставимо високий пріоритет (щоб пробивало глибокий сон Android)
        const priorityLevel = (isRestaurant || isCourier) ? "high" : "normal";

        console.log(`🚀 Відправка на топік: ${msg.topic}`);

        const fcmRes = await fetch(fcmUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken.token}`
          },
          body: JSON.stringify({
            message: {
              topic: msg.topic,
              notification: { title: msg.title, body: msg.body },
              data: { order_id: record.id.toString(), status: status },

              android: {
                priority: priorityLevel,
                notification: {
                  sound: androidSound,
                  channel_id: androidChannelId
                }
              },

              apns: {
                headers: priorityLevel === "high" ? { "apns-priority": "10" } : {},
                payload: {
                  aps: { sound: iosSound }
                }
              }
            }
          })
        });

        const rawText = await fcmRes.text();
        if (!fcmRes.ok) {
          console.error(`❌ Помилка V1 для ${msg.topic}:`, rawText);
        } else {
          console.log(`✅ Успіх для ${msg.topic}`);
        }
    }

    return new Response(JSON.stringify({ success: true }), { status: 200 })

  } catch (error) {
    console.error('❌ Push error:', error.message)
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})