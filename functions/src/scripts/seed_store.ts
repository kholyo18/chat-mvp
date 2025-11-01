import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const firestore = admin.firestore();

interface SeedProduct {
  id: string;
  data: Record<string, unknown>;
}

const seedProducts: SeedProduct[] = [
  {
    id: "coins_100",
    data: {
      title: "100 coins",
      subtitle: "Top up your wallet",
      price_cents: 199,
      currency: "USD",
      stripe_price_id: "price_coins_100",
      icon: "coins",
      active: true,
      type: "coins",
      vip_tier: null,
      coins_amount: 100,
      sort: 10,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  },
  {
    id: "vip_bronze",
    data: {
      title: "Bronze VIP",
      subtitle: "Unlock Bronze VIP perks",
      price_cents: 499,
      currency: "USD",
      stripe_price_id: "price_vip_bronze",
      icon: "vip",
      active: true,
      type: "vip",
      vip_tier: "bronze",
      coins_amount: 0,
      sort: 20,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  },
  {
    id: "theme_pro",
    data: {
      title: "Pro Theme",
      subtitle: "Unlock the pro theme",
      price_cents: 299,
      currency: "USD",
      stripe_price_id: "price_theme_pro",
      icon: "theme",
      active: true,
      type: "feature",
      vip_tier: null,
      coins_amount: 0,
      sort: 30,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  },
];

export async function seedStoreProducts(): Promise<void> {
  const batch = firestore.batch();
  for (const product of seedProducts) {
    const ref = firestore.collection("store_products").doc(product.id);
    batch.set(ref, product.data, { merge: true });
  }
  await batch.commit();
}

if (require.main === module) {
  seedStoreProducts()
    .then(() => {
      console.log("Seeded store_products successfully");
      process.exit(0);
    })
    .catch((error) => {
      console.error("Failed to seed store products", error);
      process.exit(1);
    });
}
