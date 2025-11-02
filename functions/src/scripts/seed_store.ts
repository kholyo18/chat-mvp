import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const firestore = admin.firestore();

interface SeedProduct {
  id: string;
  data: Record<string, unknown>;
}

const timestamp = admin.firestore.FieldValue.serverTimestamp();

const seedProducts: SeedProduct[] = [
  {
    id: "coins_100",
    data: {
      title: "Coins 100",
      subtitle: "Top-up your wallet",
      price_cents: 199,
      currency: "USD",
      stripe_price_id: "price_coins_100",
      icon: "coins",
      active: true,
      type: "coins",
      vip_tier: null,
      coins_amount: 100,
      sort: 10,
      createdAt: timestamp,
      updatedAt: timestamp,
    },
  },
  {
    id: "coins_500",
    data: {
      title: "Coins 500",
      subtitle: "Top-up your wallet",
      price_cents: 799,
      currency: "USD",
      stripe_price_id: "price_coins_500",
      icon: "coins",
      active: true,
      type: "coins",
      vip_tier: null,
      coins_amount: 500,
      sort: 20,
      createdAt: timestamp,
      updatedAt: timestamp,
    },
  },
  {
    id: "coins_1000",
    data: {
      title: "Coins 1000",
      subtitle: "Top-up your wallet",
      price_cents: 1499,
      currency: "USD",
      stripe_price_id: "price_coins_1000",
      icon: "coins",
      active: true,
      type: "coins",
      vip_tier: null,
      coins_amount: 1000,
      sort: 30,
      createdAt: timestamp,
      updatedAt: timestamp,
    },
  },
  {
    id: "coins_5000",
    data: {
      title: "Coins 5000",
      subtitle: "Top-up your wallet",
      price_cents: 5999,
      currency: "USD",
      stripe_price_id: "price_coins_5000",
      icon: "coins",
      active: true,
      type: "coins",
      vip_tier: null,
      coins_amount: 5000,
      sort: 40,
      createdAt: timestamp,
      updatedAt: timestamp,
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
      sort: 110,
      createdAt: timestamp,
      updatedAt: timestamp,
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
      type: "theme",
      vip_tier: null,
      coins_amount: 0,
      sort: 120,
      createdAt: timestamp,
      updatedAt: timestamp,
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
