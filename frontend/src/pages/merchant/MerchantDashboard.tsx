import React, { useEffect, useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Row,
  Col,
  Card,
  Statistic,
  Button,
  Table,
  Tag,
  Typography,
  Space,
  Tooltip,
  Modal,
  Descriptions,
  Form,
  Select,
  Input,
  message,
  Avatar,
  Badge,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import {
  ShopOutlined,
  DollarOutlined,
  TagsOutlined,
  TeamOutlined,
  CheckCircleOutlined,
  ThunderboltOutlined,
  ArrowRightOutlined,
  FileDoneOutlined,
  ReloadOutlined,
  SyncOutlined,
  CarOutlined,
  SafetyCertificateOutlined,
  InfoCircleOutlined,
  EyeOutlined,
} from '@ant-design/icons';
import { useAuth } from '../../context/AuthContext';
import { fetchDemandGroups } from '../../services/demandService';
import { fetchOffers } from '../../services/offerService';
import {
  fetchOrders,
  subscribeToOrders,
  fetchMerchantStats,
  updateOrderStatus,
} from '../../services/orderService';

const { Title, Text, Paragraph } = Typography;

export const MerchantDashboard: React.FC = () => {
  const navigate = useNavigate();
  const { user, profile } = useAuth();
  const [groups, setGroups] = useState<any[]>([]);
  const [offers, setOffers] = useState<any[]>([]);
  const [orders, setOrders] = useState<any[]>([]);
  const [merchantStats, setMerchantStats] = useState<{
    offersCount: number;
    groupsCount: number;
    ordersCount: number;
    trustScore: number | null;
    ratingCount: number;
    verifiedTier: string | null;
  }>({
    offersCount: 0,
    groupsCount: 0,
    ordersCount: 0,
    trustScore: null,
    ratingCount: 0,
    verifiedTier: null,
  });
  const [loading, setLoading] = useState(true);

  // Quick Process Order Modal State
  const [selectedOrder, setSelectedOrder] = useState<any | null>(null);
  const [processModalOpen, setProcessModalOpen] = useState(false);
  const [submittingStatus, setSubmittingStatus] = useState(false);
  const [form] = Form.useForm();

  const loadData = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    try {
      const [g, o, ord, stats] = await Promise.all([
        fetchDemandGroups().catch(() => []),
        fetchOffers({ merchantId: user.id }).catch(() => []),
        fetchOrders({ merchantId: user.id }).catch(() => []),
        fetchMerchantStats(user.id).catch(() => ({
          offersCount: 0,
          groupsCount: 0,
          ordersCount: 0,
          trustScore: null,
          ratingCount: 0,
          verifiedTier: null,
        })),
      ]);
      setGroups(g);
      setOffers(o);
      setOrders(ord);
      setMerchantStats(stats);
    } catch (err) {
      console.error('Merchant dashboard load error:', err);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    loadData();
    const unsubscribe = subscribeToOrders(() => {
      if (user?.id) {
        fetchOrders({ merchantId: user.id })
          .then((ord) => setOrders(ord || []))
          .catch(() => {});
        fetchMerchantStats(user.id)
          .then((st) => setMerchantStats(st))
          .catch(() => {});
      }
    });
    return () => {
      unsubscribe();
    };
  }, [loadData, user]);

  const handleOpenProcessModal = (record: any) => {
    setSelectedOrder(record);
    form.setFieldsValue({
      status: record.order_status || record.status || 'Confirmed',
      carrier: record.carrier || 'FedEx Commercial Freight',
      tracking_number: record.tracking_number || '',
      remarks: '',
    });
    setProcessModalOpen(true);
  };

  const handleSaveStatus = async () => {
    if (!selectedOrder) return;
    try {
      const values = await form.validateFields();
      setSubmittingStatus(true);
      await updateOrderStatus(selectedOrder.id, values.status, {
        carrier: values.carrier,
        tracking_number: values.tracking_number,
        merchant_id: user?.id,
        merchant_name: profile?.company || profile?.fullName || undefined,
        remarks: values.remarks,
      });

      message.success(`Order ${selectedOrder.order_number} progressed to "${values.status}"!`);
      setProcessModalOpen(false);
      loadData();
    } catch (err: any) {
      console.error('Failed to update status:', err);
      message.error(err.message || 'Failed to update order fulfillment status.');
    } finally {
      setSubmittingStatus(false);
    }
  };

  const groupColumns: ColumnsType<any> = [
    {
      title: 'Group Code',
      dataIndex: 'group_code',
      key: 'group_code',
      render: (code) => <Text strong style={{ color: '#1677FF' }}>{code}</Text>,
    },
    {
      title: 'Aggregated Product Demand',
      dataIndex: 'product_title',
      key: 'product_title',
      render: (title, record) => (
        <div>
          <div style={{ fontWeight: 600 }}>{title}</div>
          <Text type="secondary" style={{ fontSize: 12 }}>{record.category}</Text>
        </div>
      ),
    },
    {
      title: 'Total Volume Pool',
      dataIndex: 'total_quantity',
      key: 'total_quantity',
      render: (qty, record) => (
        <div>
          <span style={{ fontSize: 14, fontWeight: 700, color: '#172B4D' }}>{qty} units</span>
          <div style={{ fontSize: 11, color: '#6B778C' }}>{record.participants_count} pooled buyers</div>
        </div>
      ),
    },
    {
      title: 'Target Price / Unit',
      dataIndex: 'lowest_offer_price',
      key: 'lowest_offer_price',
      render: (p) => <span style={{ color: '#52C41A', fontWeight: 700 }}>${p}</span>,
    },
    {
      title: 'Bidding Status',
      dataIndex: 'status',
      key: 'status',
      render: (status) => {
        let color = 'gold';
        if (status === 'Reviewing Offers') color = 'green';
        if (status === 'Finalized') color = 'blue';
        return <Tag color={color}>{status}</Tag>;
      },
    },
    {
      title: 'Action',
      key: 'action',
      render: (_, record) => (
        <Button type="primary" size="small" onClick={() => navigate(`/merchant/offers/submit?group=${record.id}`)}>
          Submit Offer
        </Button>
      ),
    },
  ];

  const recentOrderColumns: ColumnsType<any> = [
    {
      title: 'Order ID & Date',
      dataIndex: 'order_number',
      key: 'order_number',
      render: (num, record) => (
        <div>
          <Text strong style={{ color: '#1677FF', fontFamily: 'monospace' }}>{num}</Text>
          <div style={{ fontSize: 11, color: '#64748B' }}>{record.order_date || 'Today'}</div>
        </div>
      ),
    },
    {
      title: 'Product Information',
      key: 'product',
      render: (_, record) => {
        const terms = record.accepted_terms || {};
        const img = terms.product_image || 'https://images.unsplash.com/photo-1504307651254-35680f356dfd?auto=format&fit=crop&w=120&q=80';
        return (
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Avatar shape="square" size={44} src={img} style={{ backgroundColor: '#F1F5F9', border: '1px solid #E2E8F0' }} />
            <div>
              <div style={{ fontWeight: 600, color: '#1E293B', fontSize: 13 }}>{record.product_name}</div>
              <div style={{ fontSize: 11, color: '#64748B' }}>
                {terms.brand || record.merchant_name || 'Commercial Item'} &bull; {record.quantity} {terms.unit || 'unit'}(s)
              </div>
            </div>
          </div>
        );
      },
    },
    {
      title: 'Customer & Delivery',
      key: 'customer',
      render: (_, record) => {
        const terms = record.accepted_terms || {};
        const deliv = terms.delivery_address || {};
        return (
          <div>
            <div style={{ fontWeight: 600, color: '#334155', fontSize: 12.5 }}>
              {terms.customer_name || 'Not provided'}
            </div>
            <div style={{ fontSize: 11, color: '#64748B' }}>
              {deliv.city ? `${deliv.city}, ${deliv.state || ''}` : 'Location not provided'}
            </div>
          </div>
        );
      },
    },
    {
      title: 'Escrow Value',
      dataIndex: 'total_price',
      key: 'total_price',
      render: (p, record) => (
        <div>
          <strong style={{ color: '#059669', fontSize: 13.5 }}>${Number(p).toFixed(2)}</strong>
          <div>
            <Tag color="cyan" style={{ fontSize: 10, padding: '0 4px', lineHeight: '16px' }}>
              {record.payment_status || 'Escrow Secured'}
            </Tag>
          </div>
        </div>
      ),
    },
    {
      title: 'Fulfillment Stage',
      key: 'status',
      render: (_, record) => {
        const st = record.order_status || record.status || 'Confirmed';
        let color = 'blue';
        if (st === 'Processing' || st === 'Production / Preparation') color = 'gold';
        if (st === 'Ready for Dispatch') color = 'purple';
        if (st === 'Dispatched' || st === 'Shipped' || st === 'Out for Delivery') color = 'cyan';
        if (st === 'Delivered') color = 'green';
        if (st === 'Cancelled') color = 'red';
        return (
          <Tag color={color} style={{ borderRadius: 10, fontWeight: 600 }}>
            {st}
          </Tag>
        );
      },
    },
    {
      title: 'Action',
      key: 'action',
      render: (_, record) => (
        <Space size={4}>
          <Button
            type="primary"
            size="small"
            style={{ borderRadius: 6, fontWeight: 600 }}
            onClick={() => handleOpenProcessModal(record)}
          >
            Process Order
          </Button>
          <Button
            type="text"
            size="small"
            icon={<ArrowRightOutlined />}
            onClick={() => navigate('/merchant/orders')}
          />
        </Space>
      ),
    },
  ];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      {/* Hero Welcome Card */}
      <Card
        style={{
          background: 'linear-gradient(135deg, #FFFFFF 0%, #FFFBE6 100%)',
          borderColor: '#FFE58F',
          boxShadow: '0 2px 8px rgba(250, 173, 20, 0.08)',
        }}
        styles={{ body: { padding: '24px 28px' } }}
      >
        <Row align="middle" justify="space-between" gutter={[16, 16]}>
          <Col xs={24} md={16}>
            <Space orientation="vertical" size={4}>
              <Tag color="orange" icon={<ShopOutlined />} style={{ fontWeight: 600 }}>
                MERCHANT SUPPLY PORTAL &bull; LIVE CUSTOMER ORDERS & BIDDING
              </Tag>
              <Title level={3} style={{ margin: 0, color: '#172B4D' }}>
                Welcome, {profile?.company || profile?.fullName || profile?.email || 'Merchant'}
              </Title>
              <Paragraph type="secondary" style={{ margin: 0, fontSize: 14 }}>
                Real-time commercial fulfillment hub. Review customer purchases, manage dispatch tracking, and bid on aggregated volume demand pools.
              </Paragraph>
            </Space>
          </Col>
          <Col xs={24} md={8} style={{ textAlign: 'right' }}>
            <Space>
              <Button icon={<ReloadOutlined spin={loading} />} onClick={loadData}>
                Refresh Data
              </Button>
              <Button type="primary" size="large" icon={<FileDoneOutlined />} onClick={() => navigate('/merchant/orders')}>
                Fulfillment Hub
              </Button>
            </Space>
          </Col>
        </Row>
      </Card>

      {/* Dynamic KPI Cards */}
      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} lg={6}>
          <Card variant="outlined" hoverable styles={{ body: { padding: 20 } }}>
            <Statistic
              title={<Text type="secondary" style={{ fontSize: 13 }}>Submitted Offers</Text>}
              value={offers.length || merchantStats.offersCount}
              prefix={<TagsOutlined style={{ color: '#1677FF', marginRight: 6 }} />}
              styles={{ content: { fontWeight: 700, color: '#172B4D' } }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card variant="outlined" hoverable styles={{ body: { padding: 20 } }}>
            <Statistic
              title={<Text type="secondary" style={{ fontSize: 13 }}>Open Demand Pools</Text>}
              value={groups.length || merchantStats.groupsCount}
              prefix={<TeamOutlined style={{ color: '#FAAD14', marginRight: 6 }} />}
              styles={{ content: { fontWeight: 700, color: '#172B4D' } }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card
            variant="outlined"
            hoverable
            styles={{ body: { padding: 20 } }}
            onClick={() => navigate('/merchant/orders')}
            style={{ cursor: 'pointer' }}
          >
            <Statistic
              title={<Text type="secondary" style={{ fontSize: 13 }}>Fulfillment Orders</Text>}
              value={orders.length || merchantStats.ordersCount}
              prefix={<FileDoneOutlined style={{ color: '#722ED1', marginRight: 6 }} />}
              styles={{ content: { fontWeight: 700, color: '#172B4D' } }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card variant="outlined" hoverable styles={{ body: { padding: 20 } }}>
            {merchantStats.trustScore !== null && merchantStats.trustScore > 0 ? (
              <Statistic
                title={<Text type="secondary" style={{ fontSize: 13 }}>Calculated Trust Score</Text>}
                value={merchantStats.trustScore.toFixed(1)}
                suffix="/ 5.0"
                prefix={<CheckCircleOutlined style={{ color: '#52C41A', marginRight: 6 }} />}
                styles={{ content: { fontWeight: 700, color: '#172B4D' } }}
              />
            ) : (
              <div>
                <Text type="secondary" style={{ fontSize: 13 }}>Merchant Trust Score</Text>
                <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Tag color="orange" style={{ fontWeight: 600, borderRadius: 12, padding: '2px 8px' }}>
                    Rating Pending
                  </Tag>
                  <Text type="secondary" style={{ fontSize: 12 }}>New Supplier</Text>
                </div>
              </div>
            )}
          </Card>
        </Col>
      </Row>

      {/* Live Recent Customer Fulfillment Orders */}
      <Card
        title={
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Space>
              <FileDoneOutlined style={{ color: '#722ED1' }} />
              <span style={{ fontSize: 16, fontWeight: 600 }}>Active Customer Fulfillment Orders</span>
              <Tag color="purple" style={{ borderRadius: 10, fontWeight: 600 }}>
                Live Real-Time Synchronized
              </Tag>
            </Space>
            <Button type="link" size="small" onClick={() => navigate('/merchant/orders')}>
              View All Orders ({orders.length}) <ArrowRightOutlined />
            </Button>
          </div>
        }
        variant="outlined"
      >
        {orders.length === 0 ? (
          <div style={{ padding: '36px 16px', textAlign: 'center', color: '#64748B' }}>
            <FileDoneOutlined style={{ fontSize: 36, color: '#CBD5E1', marginBottom: 12 }} />
            <div style={{ fontWeight: 600, fontSize: 15, color: '#334155' }}>No customer orders placed yet</div>
            <div style={{ fontSize: 13, marginTop: 4 }}>
              When customers purchase products from the catalog, orders will appear here dynamically in real time without refreshing.
            </div>
          </div>
        ) : (
          <Table
            columns={recentOrderColumns}
            dataSource={orders.slice(0, 5)}
            rowKey="id"
            pagination={false}
            size="middle"
          />
        )}
      </Card>

      {/* Active Customer Demand Pools */}
      <Card
        title={
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Space>
              <TeamOutlined style={{ color: '#1677FF' }} />
              <span style={{ fontSize: 16, fontWeight: 600 }}>Active Customer Demand Pools Ready for Bids</span>
            </Space>
            <Button type="link" size="small" onClick={() => navigate('/merchant/demands')}>
              View All Open Demands <ArrowRightOutlined />
            </Button>
          </div>
        }
        variant="outlined"
      >
        {groups.length === 0 ? (
          <div style={{ padding: 24, textAlign: 'center', color: '#6B778C' }}>No active demand pools yet</div>
        ) : (
          <Table columns={groupColumns} dataSource={groups} rowKey="id" pagination={false} size="middle" />
        )}
      </Card>

      {/* Quick Process Order Modal */}
      <Modal
        title={
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <SyncOutlined style={{ color: '#1677FF' }} />
            <span style={{ fontWeight: 700 }}>Quick Fulfillment Update &bull; {selectedOrder?.order_number}</span>
          </div>
        }
        open={processModalOpen}
        onCancel={() => setProcessModalOpen(false)}
        confirmLoading={submittingStatus}
        okText="Save & Push Live Update"
        cancelText="Cancel"
        onOk={handleSaveStatus}
        width={600}
      >
        {selectedOrder && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14, paddingTop: 10 }}>
            <Descriptions bordered size="small" column={2}>
              <Descriptions.Item label="Product" span={2}>
                <strong>{selectedOrder.product_name}</strong>
              </Descriptions.Item>
              <Descriptions.Item label="Quantity">{selectedOrder.quantity} units</Descriptions.Item>
              <Descriptions.Item label="Escrow Value">
                <strong style={{ color: '#059669' }}>${Number(selectedOrder.total_price).toFixed(2)}</strong>
              </Descriptions.Item>
              <Descriptions.Item label="Buyer">
                {selectedOrder.accepted_terms?.customer_name || 'Not provided'}
              </Descriptions.Item>
              <Descriptions.Item label="Destination">
                {selectedOrder.accepted_terms?.delivery_address?.city || 'San Francisco'}, {selectedOrder.accepted_terms?.delivery_address?.state || 'CA'}
              </Descriptions.Item>
            </Descriptions>

            <Form form={form} layout="vertical" style={{ marginTop: 8 }}>
              <Form.Item
                name="status"
                label="Fulfillment Stage"
                rules={[{ required: true, message: 'Please select a fulfillment stage' }]}
              >
                <Select
                  options={[
                    { label: 'Confirmed (Order Confirmed in Escrow)', value: 'Confirmed' },
                    { label: 'Processing (Inventory Allocation / Batching)', value: 'Processing' },
                    { label: 'Production / Preparation (Manufacturing & Packaging)', value: 'Production / Preparation' },
                    { label: 'Ready for Dispatch (Inspected & Staged for Pickup)', value: 'Ready for Dispatch' },
                    { label: 'Shipped (Carrier Dispatched in Transit)', value: 'Shipped' },
                    { label: 'Out for Delivery (Local Distribution Hub)', value: 'Out for Delivery' },
                    { label: 'Delivered (Destination Reached & Handed Over)', value: 'Delivered' },
                    { label: 'Cancelled', value: 'Cancelled' },
                  ]}
                />
              </Form.Item>

              <Row gutter={12}>
                <Col span={12}>
                  <Form.Item name="carrier" label="Logistics Carrier">
                    <Select
                      options={[
                        { label: 'FedEx Commercial Freight', value: 'FedEx Commercial Freight' },
                        { label: 'DHL Express Global', value: 'DHL Express Global' },
                        { label: 'UPS Supply Chain Solutions', value: 'UPS Supply Chain Solutions' },
                        { label: 'Direct Merchant Fleet', value: 'Direct Merchant Fleet' },
                        { label: 'Maersk Regional Logistics', value: 'Maersk Regional Logistics' },
                      ]}
                    />
                  </Form.Item>
                </Col>
                <Col span={12}>
                  <Form.Item name="tracking_number" label="Tracking / Waybill Number">
                    <Input placeholder="e.g. FDX-892401-US" />
                  </Form.Item>
                </Col>
              </Row>

              <Form.Item name="remarks" label="Fulfillment Remarks / Handling Notes">
                <Input.TextArea rows={2} placeholder="e.g., Cargo palletized and loaded on carrier vehicle." />
              </Form.Item>
            </Form>

            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: '#059669', background: '#F0FDF4', padding: '8px 12px', borderRadius: 6 }}>
              <SafetyCertificateOutlined />
              <span>Updating this stage immediately reflects across the Customer dashboard in real time.</span>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
};

export default MerchantDashboard;
