import { axiosClient } from './axiosClient';

export interface Product {
  id: string;
  name: string;
  slug: string;
  description: string;
  category: string;
  brand: string;
  model_number: string;
  specifications: Record<string, any>;
  unit: string;
  retail_price: number;
  wholesale_price: number;
  minimum_order_quantity: number;
  available_quantity: number;
  images: string[];
  status: 'active' | 'inactive';
  created_by?: string | null;
  created_at?: string;
  updated_at?: string;
  // Compatibility aliases
  market_price?: number;
  min_demand_price?: number;
  in_stock?: boolean;
  image_url?: string;
  sku?: string;
  rating?: number;
  reviews_count?: number;
  activeDemandsCount?: number;
}

export interface ProductMatchItem extends Product {
  match_type: 'exact' | 'similar' | 'alternative' | 'related';
  match_tier?: 'exact' | 'similar' | 'alternative' | 'related';
  relevance_score: number;
  match_reasons: string[];
  matching_attributes?: string[];
  different_attributes?: string[];
  compatibility_explanation?: string;
}

export interface ProductQueryParams {
  page?: number;
  page_size?: number;
  search?: string;
  category?: string;
  min_price?: number;
  max_price?: number;
  sort_by?: 'newest' | 'price_asc' | 'price_desc' | 'popular';
}

export interface ProductSearchParams {
  q?: string;
  category?: string;
  min_price?: number;
  max_price?: number;
  sort?: 'relevance' | 'price_asc' | 'price_desc' | 'newest';
  page?: number;
  page_size?: number;
}

export interface ProductListResponse {
  items: Product[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

export interface ProductSearchResponse {
  items: ProductMatchItem[];
  exact_matches: ProductMatchItem[];
  similar_matches: ProductMatchItem[];
  alternative_matches?: ProductMatchItem[];
  related_matches?: ProductMatchItem[];
  total: number;
  exact_count: number;
  similar_count: number;
  alternative_count?: number;
  related_count?: number;
  page: number;
  page_size: number;
  total_pages: number;
  query: string;
  has_exact_match: boolean;
  suggestion_message?: string | null;
}

export interface ProductMatchRequest {
  query?: string;
  category?: string;
  specifications?: Record<string, any>;
  target_price?: number;
  target_quantity?: number;
}

export interface ProductMatchResponse {
  matches: ProductMatchItem[];
  exact_matches?: ProductMatchItem[];
  similar_matches?: ProductMatchItem[];
  alternative_matches?: ProductMatchItem[];
  related_matches?: ProductMatchItem[];
  has_exact_match: boolean;
  exact_match_count: number;
  similar_match_count: number;
  alternative_match_count?: number;
  related_match_count?: number;
  recommendation: 'use_catalog' | 'view_alternatives' | 'create_demand';
  create_demand_params: Record<string, any>;
}

export interface CreateProductPayload {
  name: string;
  slug?: string;
  description?: string;
  category: string;
  brand?: string;
  model_number?: string;
  specifications?: Record<string, any>;
  unit?: string;
  retail_price: number;
  wholesale_price: number;
  minimum_order_quantity?: number;
  available_quantity?: number;
  images?: string[];
  status?: 'active' | 'inactive';
}

export const productApi = {
  /**
   * Fetch active catalog products with pagination, search, category filter, price bounds and sorting
   */
  async getProducts(params?: ProductQueryParams): Promise<ProductListResponse> {
    const res = await axiosClient.get<ProductListResponse>('/api/products', { params });
    return res.data;
  },

  /**
   * Phase 6 Core Search: Search products with relevance ranking, exact vs similar classification, and match explanations
   */
  async searchProducts(params?: ProductSearchParams): Promise<ProductSearchResponse> {
    const res = await axiosClient.get<ProductSearchResponse>('/api/products/search', { params });
    return res.data;
  },

  /**
   * Phase 6 Matching: Match customer requirement parameters or specs against existing catalogue
   */
  async matchProduct(payload: ProductMatchRequest): Promise<ProductMatchResponse> {
    const res = await axiosClient.post<ProductMatchResponse>('/api/products/match', payload);
    return res.data;
  },

  /**
   * Fetch distinct active product taxonomy categories
   */
  async getCategories(): Promise<string[]> {
    const res = await axiosClient.get<string[]>('/api/products/categories');
    return res.data;
  },

  /**
   * Fetch single product details by UUID or unique slug
   */
  async getProductById(idOrSlug: string): Promise<Product> {
    const res = await axiosClient.get<Product>(`/api/products/${idOrSlug}`);
    return res.data;
  },

  /**
   * Fetch personalized product recommendations for the customer
   */
  async getRecommendations(userId?: string, limit: number = 8): Promise<Product[]> {
    const res = await axiosClient.get<Product[]>('/api/products/recommendations', {
      params: { user_id: userId, limit },
    });
    return res.data;
  },

  /**
   * Fetch popular marketplace products
   */
  async getPopularProducts(limit: number = 8): Promise<Product[]> {
    const res = await axiosClient.get<Product[]>('/api/products/popular', {
      params: { limit },
    });
    return res.data;
  },

  /**
   * Fetch recently added products
   */
  async getRecentlyAddedProducts(limit: number = 8): Promise<Product[]> {
    const res = await axiosClient.get<Product[]>('/api/products/recent', {
      params: { limit },
    });
    return res.data;
  },

  /**
   * Fetch similar, alternative, and related products for a product ID
   */
  async getSimilarAndAlternatives(
    productId: string,
    limit: number = 6
  ): Promise<{ similar: ProductMatchItem[]; alternatives: ProductMatchItem[]; related: ProductMatchItem[] }> {
    const res = await axiosClient.get<{
      similar: ProductMatchItem[];
      alternatives: ProductMatchItem[];
      related: ProductMatchItem[];
    }>(`/api/products/${productId}/similar`, {
      params: { limit },
    });
    return res.data;
  },
};
