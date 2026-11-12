/**
 * MarketTwin Mock Data Store
 * Powers Customer and Merchant modules with realistic demand-driven marketplace data.
 */

export interface ProductItem {
  id: string;
  name: string;
  category: string;
  sku: string;
  description: string;
  marketPrice: number;
  minDemandPrice: number;
  rating: number;
  reviewsCount: number;
  inStock: boolean;
  image: string;
  specs: Record<string, string>;
  activeDemandsCount: number;
}

export interface DemandItem {
  id: string;
  demandCode: string;
  title: string;
  category: string;
  targetPrice: number;
  marketPrice: number;
  targetQuantity: number;
  currentGroupQuantity: number;
  groupThreshold: number;
  status: 'Pending' | 'Grouped' | 'Offers Received' | 'Approved' | 'Completed';
  createdAt: string;
  deadline: string;
  description: string;
  specs: Record<string, string>;
  groupId?: string;
  offersCount: number;
  customerName: string;
  customerEmail: string;
}

export interface DemandGroupItem {
  id: string;
  groupCode: string;
  productTitle: string;
  category: string;
  totalQuantity: number;
  thresholdQuantity: number;
  participantsCount: number;
  estimatedSavings: number;
  status: 'Forming' | 'Open for Bidding' | 'Reviewing Offers' | 'Finalized';
  deadline: string;
  lowestOfferPrice?: number;
  offersCount: number;
  topOfferMerchant?: string;
}

export interface OfferItem {
  id: string;
  offerCode: string;
  demandId: string;
  demandTitle: string;
  merchantId: string;
  merchantName: string;
  merchantRating: number;
  unitPrice: number;
  originalTargetPrice: number;
  totalOfferAmount: number;
  minOrderQuantity: number;
  deliveryDays: number;
  warrantyMonths: number;
  status: 'Submitted' | 'Under Review' | 'Customer Approved' | 'Rejected';
  submittedDate: string;
  specNotes: string;
  shippingTerms: string;
}

export interface OrderItem {
  id: string;
  orderNumber: string;
  demandCode: string;
  productName: string;
  merchantName: string;
  quantity: number;
  totalPrice: number;
  status: 'Approved' | 'Processing' | 'Dispatched' | 'Delivered' | 'Cancelled';
  orderDate: string;
  estimatedDelivery: string;
  trackingNumber: string;
  carrier: string;
  currentStep: number;
}

export interface NotificationItem {
  id: string;
  title: string;
  description: string;
  time: string;
  type: 'demand' | 'offer' | 'order' | 'system';
  unread: boolean;
  actionUrl?: string;
}

// 1. Initial Products
export const mockProducts: ProductItem[] = [
  {
    id: 'prod-1',
    name: 'Ergonomic Mesh High-Back Executive Chair',
    category: 'Office Furniture',
    sku: 'FURN-CH-409',
    description: 'Adjustable 4D armrests, lumbar support system, and breathable Italian mesh.',
    marketPrice: 320,
    minDemandPrice: 210,
    rating: 4.8,
    reviewsCount: 124,
    inStock: true,
    image: 'https://images.unsplash.com/photo-1580481077195-c3a82da91883?auto=format&fit=crop&w=400&q=80',
    specs: {
      'Weight Capacity': '150 kg',
      'Material': 'High-Density Mesh & Aluminum Base',
      'Warranty': '3 Years Commercial Warranty',
      'Mechanism': 'Multi-angle Synchro-tilt',
    },
    activeDemandsCount: 14,
  },
  {
    id: 'prod-2',
    name: 'Commercial Solar Inverter 10kW 3-Phase',
    category: 'Renewable Energy',
    sku: 'SOLAR-INV-10K',
    description: 'High efficiency dual-MPPT hybrid inverter with smart cloud monitoring.',
    marketPrice: 1850,
    minDemandPrice: 1390,
    rating: 4.9,
    reviewsCount: 88,
    inStock: true,
    image: 'https://images.unsplash.com/photo-1509391365360-2e959784a276?auto=format&fit=crop&w=400&q=80',
    specs: {
      'Max Efficiency': '98.6%',
      'Nominal Power': '10,000 W',
      'Grid Standard': 'UL1741-SA / IEEE 1547',
      'Ingress Protection': 'IP65 Weatherproof',
    },
    activeDemandsCount: 9,
  },
  {
    id: 'prod-3',
    name: 'Specialty Dual-Boiler Commercial Espresso Machine',
    category: 'Commercial Kitchen',
    sku: 'KIT-ESP-880',
    description: 'Dual insulated stainless steel boilers, PID digital temperature control, and rotary pump.',
    marketPrice: 3400,
    minDemandPrice: 2650,
    rating: 4.7,
    reviewsCount: 42,
    inStock: false,
    image: 'https://images.unsplash.com/photo-1514432324607-a09d9b4aefdd?auto=format&fit=crop&w=400&q=80',
    specs: {
      'Boiler Capacity': '4.5 L Steam + 1.2 L Brew',
      'Power Rating': '2800W / 240V',
      'Group Head': 'Commercial 58mm E61 Style',
      'Origin': 'Handcrafted Italy',
    },
    activeDemandsCount: 18,
  },
  {
    id: 'prod-4',
    name: '4K Laser Ultra-Short-Throw Projector (3000 Lumens)',
    category: 'Electronics',
    sku: 'ELEC-PROJ-4K',
    description: 'HDR10+ true 4K UHD projection up to 150 inches with built-in Harman Kardon acoustics.',
    marketPrice: 2199,
    minDemandPrice: 1650,
    rating: 4.6,
    reviewsCount: 76,
    inStock: true,
    image: 'https://images.unsplash.com/photo-1535016120720-40c646be5580?auto=format&fit=crop&w=400&q=80',
    specs: {
      'Native Resolution': '3840 x 2160 UHD',
      'Light Source': 'ALPD 4.0 Laser',
      'Audio Output': '60W Dolby Atmos Soundbar',
      'Throw Ratio': '0.23:1 Ultra Short Throw',
    },
    activeDemandsCount: 7,
  },
  {
    id: 'prod-5',
    name: 'Ceremonial Grade Uji Matcha (Bulk Pack 5kg)',
    category: 'Food & Beverage',
    sku: 'FNB-MTC-5KG',
    description: 'First harvest stone-ground green tea leaves from Kyoto, Japan. Certified organic.',
    marketPrice: 480,
    minDemandPrice: 340,
    rating: 4.9,
    reviewsCount: 210,
    inStock: true,
    image: 'https://images.unsplash.com/photo-1576092768241-dec231879fc3?auto=format&fit=crop&w=400&q=80',
    specs: {
      'Cultivar': 'Yabukita & Okumidori',
      'Packaging': 'Nitrogen flushed 1kg vacuum sealed bags',
      'Certifications': 'JAS Organic / USDA Organic',
      'Shelf Life': '18 Months',
    },
    activeDemandsCount: 22,
  },
];

// 2. Initial Demands
export const mockDemands: DemandItem[] = [
  {
    id: 'dem-101',
    demandCode: 'DEM-2026-081',
    title: 'Ergonomic Executive Office Chair with Footrest',
    category: 'Office Furniture',
    targetPrice: 210,
    marketPrice: 320,
    targetQuantity: 10,
    currentGroupQuantity: 42,
    groupThreshold: 50,
    status: 'Grouped',
    createdAt: '2026-10-24',
    deadline: '2026-11-15',
    description: 'Looking for 10 units for new coworking floor. Must include 4D armrests, headrest, and black breathable mesh.',
    specs: { 'Color': 'Matte Black', 'Armrest': '4D Adjustable', 'Base': 'Polished Aluminum' },
    offersCount: 3,
    customerName: 'Alex Mercer',
    customerEmail: 'alex.mercer@techstart.io',
  },
  {
    id: 'dem-102',
    demandCode: 'DEM-2026-084',
    title: '10kW 3-Phase Commercial Solar Inverters',
    category: 'Renewable Energy',
    targetPrice: 1400,
    marketPrice: 1850,
    targetQuantity: 4,
    currentGroupQuantity: 16,
    groupThreshold: 15,
    status: 'Offers Received',
    createdAt: '2026-10-27',
    deadline: '2026-11-10',
    description: 'Requirement for small commercial solar installation rooftop cluster. UL1741-SA certified.',
    specs: { 'Grid': 'Three-Phase 400V', 'MPPT': 'Dual Tracker', 'Monitoring': 'Wi-Fi / Ethernet module' },
    offersCount: 4,
    customerName: 'Sarah Jenkins',
    customerEmail: 'sarah.j@greenpower.co',
  },
  {
    id: 'dem-103',
    demandCode: 'DEM-2026-092',
    title: 'Organic Ceremonial Matcha 5kg Bulk Order',
    category: 'Food & Beverage',
    targetPrice: 350,
    marketPrice: 480,
    targetQuantity: 2,
    currentGroupQuantity: 18,
    groupThreshold: 20,
    status: 'Pending',
    createdAt: '2026-11-01',
    deadline: '2026-11-20',
    description: 'Specialty cafe seasonal supply. Need autumn first flush matcha with vivid green color and sweet umami taste.',
    specs: { 'Harvest': 'First Flush', 'Certificate': 'USDA Organic', 'Origin': 'Kyoto Prefecture' },
    offersCount: 1,
    customerName: 'Marcus Wong',
    customerEmail: 'marcus@brewlabcafe.com',
  },
  {
    id: 'dem-104',
    demandCode: 'DEM-2026-065',
    title: 'Commercial Dual-Boiler Espresso Station',
    category: 'Commercial Kitchen',
    targetPrice: 2700,
    marketPrice: 3400,
    targetQuantity: 1,
    currentGroupQuantity: 6,
    groupThreshold: 5,
    status: 'Approved',
    createdAt: '2026-10-15',
    deadline: '2026-11-05',
    description: 'Station upgrade. Approved merchant offer from BaristaCraft Global.',
    specs: { 'Voltage': '240V 60Hz', 'Pump': 'Commercial Rotary', 'Steam Wand': 'Cool-Touch Dual' },
    offersCount: 5,
    customerName: 'Alex Mercer',
    customerEmail: 'alex.mercer@techstart.io',
  },
];

// 3. Initial Demand Groups
export const mockDemandGroups: DemandGroupItem[] = [
  {
    id: 'grp-01',
    groupCode: 'GRP-OFFICE-50',
    productTitle: 'Ergonomic Executive Office Chair with Footrest',
    category: 'Office Furniture',
    totalQuantity: 42,
    thresholdQuantity: 50,
    participantsCount: 6,
    estimatedSavings: 4620,
    status: 'Forming',
    deadline: '2026-11-15',
    lowestOfferPrice: 205,
    offersCount: 3,
    topOfferMerchant: 'Apex Workspace Solutions',
  },
  {
    id: 'grp-02',
    groupCode: 'GRP-SOLAR-15',
    productTitle: '10kW 3-Phase Commercial Solar Inverters',
    category: 'Renewable Energy',
    totalQuantity: 16,
    thresholdQuantity: 15,
    participantsCount: 4,
    estimatedSavings: 7200,
    status: 'Reviewing Offers',
    deadline: '2026-11-10',
    lowestOfferPrice: 1380,
    offersCount: 4,
    topOfferMerchant: 'Helios Industrial Tech',
  },
  {
    id: 'grp-03',
    groupCode: 'GRP-MATCHA-20',
    productTitle: 'Organic Ceremonial Matcha 5kg Bulk Order',
    category: 'Food & Beverage',
    totalQuantity: 18,
    thresholdQuantity: 20,
    participantsCount: 8,
    estimatedSavings: 2340,
    status: 'Forming',
    deadline: '2026-11-20',
    lowestOfferPrice: 345,
    offersCount: 2,
    topOfferMerchant: 'Kyoto Imports Direct',
  },
  {
    id: 'grp-04',
    groupCode: 'GRP-ESPRESSO-05',
    productTitle: 'Commercial Dual-Boiler Espresso Station',
    category: 'Commercial Kitchen',
    totalQuantity: 6,
    thresholdQuantity: 5,
    participantsCount: 5,
    estimatedSavings: 4200,
    status: 'Finalized',
    deadline: '2026-11-05',
    lowestOfferPrice: 2650,
    offersCount: 5,
    topOfferMerchant: 'BaristaCraft Global',
  },
];

// 4. Initial Merchant Offers
export const mockOffers: OfferItem[] = [
  {
    id: 'off-501',
    offerCode: 'OFF-2026-301',
    demandId: 'dem-101',
    demandTitle: 'Ergonomic Executive Office Chair with Footrest',
    merchantId: 'merch-01',
    merchantName: 'Apex Workspace Solutions',
    merchantRating: 4.9,
    unitPrice: 205,
    originalTargetPrice: 210,
    totalOfferAmount: 8610,
    minOrderQuantity: 30,
    deliveryDays: 7,
    warrantyMonths: 36,
    status: 'Under Review',
    submittedDate: '2026-10-30',
    specNotes: 'Exceeds ANSI/BIFMA X5.1 standard. BIFMA certified class 4 gas lift included.',
    shippingTerms: 'Free doorstep pallet delivery with insurance included.',
  },
  {
    id: 'off-502',
    offerCode: 'OFF-2026-302',
    demandId: 'dem-101',
    demandTitle: 'Ergonomic Executive Office Chair with Footrest',
    merchantId: 'merch-02',
    merchantName: 'ErgoDesign Direct',
    merchantRating: 4.7,
    unitPrice: 215,
    originalTargetPrice: 210,
    totalOfferAmount: 9030,
    minOrderQuantity: 25,
    deliveryDays: 5,
    warrantyMonths: 48,
    status: 'Under Review',
    submittedDate: '2026-10-31',
    specNotes: 'Customized mesh fabric with high breathability. Includes 4-year replacement warranty.',
    shippingTerms: 'Flat rate expedited freight.',
  },
  {
    id: 'off-503',
    offerCode: 'OFF-2026-303',
    demandId: 'dem-102',
    demandTitle: '10kW 3-Phase Commercial Solar Inverters',
    merchantId: 'merch-03',
    merchantName: 'Helios Industrial Tech',
    merchantRating: 4.9,
    unitPrice: 1380,
    originalTargetPrice: 1400,
    totalOfferAmount: 22080,
    minOrderQuantity: 10,
    deliveryDays: 10,
    warrantyMonths: 60,
    status: 'Under Review',
    submittedDate: '2026-10-29',
    specNotes: 'Includes factory RS485 and Wi-Fi dongles. 5-year full manufacturer warranty.',
    shippingTerms: 'Crated liftgate freight direct to installation sites.',
  },
  {
    id: 'off-504',
    offerCode: 'OFF-2026-304',
    demandId: 'dem-104',
    demandTitle: 'Commercial Dual-Boiler Espresso Station',
    merchantId: 'merch-04',
    merchantName: 'BaristaCraft Global',
    merchantRating: 4.8,
    unitPrice: 2650,
    originalTargetPrice: 2700,
    totalOfferAmount: 15900,
    minOrderQuantity: 5,
    deliveryDays: 12,
    warrantyMonths: 24,
    status: 'Customer Approved',
    submittedDate: '2026-10-22',
    specNotes: 'Custom satin steel side panels and bottomless portafilters included.',
    shippingTerms: 'White-glove technician delivery and on-site calibration included.',
  },
];

// 5. Initial Orders
export const mockOrders: OrderItem[] = [
  {
    id: 'ord-801',
    orderNumber: 'MT-ORD-9401',
    demandCode: 'DEM-2026-065',
    productName: 'Commercial Dual-Boiler Espresso Station',
    merchantName: 'BaristaCraft Global',
    quantity: 1,
    totalPrice: 2650,
    status: 'Processing',
    orderDate: '2026-10-28',
    estimatedDelivery: '2026-11-09',
    trackingNumber: 'TRK-FEDEX-882910',
    carrier: 'FedEx Freight',
    currentStep: 1, // 0: Approved, 1: Processing, 2: Dispatched, 3: Delivered
  },
  {
    id: 'ord-802',
    orderNumber: 'MT-ORD-9388',
    demandCode: 'DEM-2026-031',
    productName: '4K Laser Ultra-Short-Throw Projector',
    merchantName: 'VisionCraft Tech',
    quantity: 1,
    totalPrice: 1620,
    status: 'Dispatched',
    orderDate: '2026-10-18',
    estimatedDelivery: '2026-11-04',
    trackingNumber: 'TRK-UPS-412093',
    carrier: 'UPS Express',
    currentStep: 2,
  },
  {
    id: 'ord-803',
    orderNumber: 'MT-ORD-9102',
    demandCode: 'DEM-2026-012',
    productName: 'Ergonomic Mesh Chair Batch #1',
    merchantName: 'Apex Workspace Solutions',
    quantity: 5,
    totalPrice: 1050,
    status: 'Delivered',
    orderDate: '2026-09-14',
    estimatedDelivery: '2026-09-22',
    trackingNumber: 'TRK-DHL-918231',
    carrier: 'DHL Freight',
    currentStep: 3,
  },
];

// 6. Initial Notifications
export const mockNotifications: NotificationItem[] = [
  {
    id: 'notif-1',
    title: 'New Merchant Offer Received',
    description: 'Apex Workspace Solutions submitted an offer of $205/unit for DEM-2026-081.',
    time: '15 mins ago',
    type: 'offer',
    unread: true,
  },
  {
    id: 'notif-2',
    title: 'Demand Group Threshold Reached!',
    description: 'Group GRP-SOLAR-15 reached 16 units (Threshold: 15). Merchants are reviewing specifications.',
    time: '2 hours ago',
    type: 'demand',
    unread: true,
  },
  {
    id: 'notif-3',
    title: 'Order Dispatched',
    description: 'Order MT-ORD-9388 has been dispatched via UPS Express (Tracking: TRK-UPS-412093).',
    time: 'Yesterday',
    type: 'order',
    unread: false,
  },
  {
    id: 'notif-4',
    title: 'FastAPI Backend Operational',
    description: 'System health check confirmed all services are responsive.',
    time: 'Today',
    type: 'system',
    unread: false,
  },
];
