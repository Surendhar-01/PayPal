import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Card,
  Table,
  Tag,
  Button,
  Space,
  Typography,
  Modal,
  Select,
  Input,
  DatePicker,
  Form,
  message,
  Descriptions,
  Badge,
  Tooltip,
  Row,
  Col,
  Statistic,
  Tabs,
  Avatar,
  Divider,
  Steps,
  Timeline,
  Alert,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import {
  CarOutlined,
  ReloadOutlined,
  CheckCircleOutlined,
  SyncOutlined,
  SendOutlined,
  FileTextOutlined,
  DollarOutlined,
  SafetyCertificateOutlined,
  SearchOutlined,
  FilterOutlined,
  EyeOutlined,
  ClockCircleOutlined,
  EnvironmentOutlined,
  UserOutlined,
  BarcodeOutlined,
  InboxOutlined,
  CheckOutlined,
  CloseCircleOutlined,
} from '@ant-design/icons';
import { useAuth } from '../../context/AuthContext';
import {
  fetchOrders,
  fetchOrderDetails,
  updateOrderStatus,
  subscribeToOrders,
} from '../../services/orderService';

const { Title, Text, Paragraph } = Typography;

export const MerchantOrders: React.FC = () => {
  const navigate = useNavigate();
  const { user, profile } = useAuth();
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  // Search, Filter, Sort State
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [sortBy, setSortBy] = useState('newest');

  // Order Details Modal State
  const [detailModalOpen, setDetailModalOpen] = useState(false);
  const [activeOrderDetails, setActiveOrderDetails] = useState<any | null>(null);
  const [loadingDetails, setLoadingDetails] = useState(false);
  const [activeTabKey, setActiveTabKey] = useState('summary');

  // Status Update Form State
  const [submittingStatus, setSubmittingStatus] = useState(false);
  const [form] = Form.useForm();

  const loadOrders = useCallback(async () => {
    if (!user) {
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const data = await fetchOrders({ merchantId: user.id });
      setOrders(data);
    } catch (err) {
      console.error('Error fetching merchant orders:', err);
    } finally {
      setLoading(false);
    }
  }, [user]);

  // Initial load and Real-time subscription to orders table
  useEffect(() => {
    loadOrders();
    const unsubscribe = subscribeToOrders(() => {
      loadOrders();
    });
    return () => {
      unsubscribe();
    };
  }, [loadOrders]);

  // Open Full Order Details Modal
  const handleOpenDetails = async (record: any, defaultTab = 'summary') => {
    setActiveTabKey(defaultTab);
    setDetailModalOpen(true);
    setLoadingDetails(true);
    try {
      const fullDetails = await fetchOrderDetails(record.id);
      setActiveOrderDetails(fullDetails);
      form.setFieldsValue({
        status: fullDetails.order_status || fullDetails.status || 'Confirmed',
        carrier: fullDetails.carrier || 'FedEx Commercial Freight',
        tracking_number: fullDetails.tracking_number || '',
        remarks: '',
      });
    } catch (err) {
      console.warn('Could not load extra relations, using record:', err);
      setActiveOrderDetails(record);
      form.setFieldsValue({
        status: record.order_status || record.status || 'Confirmed',
        carrier: record.carrier || 'FedEx Commercial Freight',
        tracking_number: record.tracking_number || '',
        remarks: '',
      });
    } finally {
      setLoadingDetails(false);
    }
  };

  const handleUpdateStatus = async () => {
    if (!activeOrderDetails) return;
    try {
      const values = await form.validateFields();
      setSubmittingStatus(true);
      await updateOrderStatus(activeOrderDetails.id, values.status, {
        carrier: values.carrier,
        tracking_number: values.tracking_number,
        merchant_id: user?.id,
        merchant_name: profile?.company || profile?.fullName || undefined,
        remarks: values.remarks,
      });

      message.success(`Order ${activeOrderDetails.order_number} status updated to "${values.status}"!`);
      // Reload order details
      const refreshed = await fetchOrderDetails(activeOrderDetails.id);
      setActiveOrderDetails(refreshed);
      loadOrders();
    } catch (err: any) {
      console.error('Failed to update status:', err);
      message.error(err.message || 'Failed to update order status.');
    } finally {
      setSubmittingStatus(false);
    }
  };

  // Filtered & Sorted orders
  const filteredOrders = useMemo(() => {
    let result = [...orders];

    // Search filter
    if (searchTerm.trim()) {
      const q = searchTerm.toLowerCase();
      result = result.filter((o) => {
        const orderNum = (o.order_number || '').toLowerCase();
        const prod = (o.product_name || '').toLowerCase();
        const date = (o.order_date || '').toLowerCase();
        const cust = (o.accepted_terms?.customer_name || '').toLowerCase();
        const city = (o.accepted_terms?.delivery_address?.city || '').toLowerCase();
        return (
          orderNum.includes(q) ||
          prod.includes(q) ||
          date.includes(q) ||
          cust.includes(q) ||
          city.includes(q)
        );
      });
    }

    // Status filter
    if (statusFilter !== 'ALL') {
      result = result.filter((o) => {
        const stage = (o.order_status || o.status || '').toLowerCase();
        const target = statusFilter.toLowerCase();
        if (target === 'confirmed') return stage.includes('confirm') || stage.includes('approved');
        if (target === 'processing') return stage.includes('process');
        if (target === 'production') return stage.includes('production') || stage.includes('prep');
        if (target === 'ready_dispatch') return stage.includes('ready') || stage.includes('dispatch');
        if (target === 'shipped') return stage.includes('ship') || stage.includes('transit');
        if (target === 'out_delivery') return stage.includes('out') || stage.includes('delivery');
        if (target === 'delivered') return stage.includes('delivered');
        if (target === 'cancelled') return stage.includes('cancel');
        if (target === 'payment_pending') return (o.payment_status || '').toLowerCase().includes('pending');
        return stage.includes(target);
      });
    }

    // Sorting
    result.sort((a, b) => {
      if (sortBy === 'newest') {
        return new Date(b.created_at || b.order_date).getTime() - new Date(a.created_at || a.order_date).getTime();
      }
      if (sortBy === 'oldest') {
        return new Date(a.created_at || a.order_date).getTime() - new Date(b.created_at || b.order_date).getTime();
      }
      if (sortBy === 'highest_value') {
        return Number(b.total_price || 0) - Number(a.total_price || 0);
      }
      if (sortBy === 'lowest_value') {
        return Number(a.total_price || 0) - Number(b.total_price || 0);
      }
      return 0;
    });

    return result;
  }, [orders, searchTerm, statusFilter, sortBy]);

  // Metrics summary
  const metrics = useMemo(() => {
    const total = orders.length;
    let awaitingDispatch = 0;
    let inTransit = 0;
    let delivered = 0;
    let totalGross = 0;

    orders.forEach((o) => {
      const st = (o.order_status || o.status || '').toLowerCase();
      const price = Number(o.total_price || 0);
      totalGross += price;
      if (st.includes('approved') || st.includes('confirm') || st.includes('process') || st.includes('ready')) {
        awaitingDispatch++;
      } else if (st.includes('ship') || st.includes('transit') || st.includes('out')) {
        inTransit++;
      } else if (st.includes('delivered')) {
        delivered++;
      }
    });

    return { total, awaitingDispatch, inTransit, delivered, totalGross };
  }, [orders]);

  const columns: ColumnsType<any> = [
    {
      title: 'Order ID & Date',
      dataIndex: 'order_number',
      key: 'order_number',
      render: (num, record) => (
        <div>
          <Text strong style={{ color: '#1677FF', fontFamily: 'monospace', fontSize: 13 }}>
            {num}
          </Text>
          <div style={{ fontSize: 11, color: '#94A3B8' }}>{record.order_date || 'Recent'}</div>
        </div>
      ),
    },
    {
      title: 'Customer & Destination',
      key: 'customer',
      render: (_, record) => {
        const terms = record.accepted_terms || {};
        const deliv = terms.delivery_address || {};
        return (
          <div>
            <div style={{ fontWeight: 600, color: '#1E293B', fontSize: 13 }}>
              {terms.customer_name || 'Not provided'}
            </div>
            <div style={{ fontSize: 11, color: '#64748B' }}>
              <EnvironmentOutlined style={{ marginRight: 4 }} />
              {deliv.city ? `${deliv.city}, ${deliv.state || ''}` : 'Location not provided'}
            </div>
          </div>
        );
      },
    },
    {
      title: 'Product Information',
      key: 'product_name',
      render: (_, record) => {
        const terms = record.accepted_terms || {};
        const img =
          terms.product_image ||
          'https://images.unsplash.com/photo-1504307651254-35680f356dfd?auto=format&fit=crop&w=120&q=80';
        return (
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Avatar
              shape="square"
              size={42}
              src={img}
              style={{ backgroundColor: '#F8FAFC', border: '1px solid #E2E8F0' }}
            />
            <div>
              <div style={{ fontWeight: 600, color: '#172B4D', fontSize: 13 }}>{record.product_name}</div>
              <div style={{ fontSize: 11, color: '#64748B' }}>
                {terms.brand || record.merchant_name || 'Commercial Item'}
              </div>
            </div>
          </div>
        );
      },
    },
    {
      title: 'Quantity',
      dataIndex: 'quantity',
      key: 'quantity',
      render: (q, record) => {
        const unit = record.accepted_terms?.unit || 'unit';
        return <span style={{ fontWeight: 600, color: '#334155' }}>{q} {unit}(s)</span>;
      },
    },
    {
      title: 'Escrow Value',
      dataIndex: 'total_price',
      key: 'total_price',
      render: (p, record) => (
        <div>
          <span style={{ fontWeight: 700, color: '#059669', fontSize: 14 }}>
            ${Number(p).toFixed(2)}
          </span>
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
        const status = record.order_status || record.status || 'Confirmed';
        let color = 'blue';
        if (status === 'Processing' || status === 'Production / Preparation') color = 'gold';
        if (status === 'Ready for Dispatch') color = 'purple';
        if (status === 'Dispatched' || status === 'Shipped' || status === 'Out for Delivery') color = 'cyan';
        if (status === 'Delivered') color = 'green';
        if (status === 'Cancelled') color = 'red';
        return (
          <Tag color={color} style={{ borderRadius: 10, fontWeight: 600 }}>
            {status}
          </Tag>
        );
      },
    },
    {
      title: 'Logistics Carrier',
      key: 'tracking',
      render: (_, record) =>
        record.tracking_number ? (
          <div>
            <div style={{ fontWeight: 600, fontSize: 12, color: '#1E293B' }}>{record.carrier || 'Logistics'}</div>
            <Text type="secondary" style={{ fontSize: 11, fontFamily: 'monospace' }}>
              {record.tracking_number}
            </Text>
          </div>
        ) : (
          <Text type="secondary" style={{ fontSize: 11, fontStyle: 'italic' }}>
            Awaiting dispatch
          </Text>
        ),
    },
    {
      title: 'Actions',
      key: 'actions',
      render: (_, record) => (
        <Space size={6}>
          <Button
            size="small"
            icon={<EyeOutlined />}
            onClick={() => handleOpenDetails(record, 'summary')}
            style={{ borderRadius: 6, fontWeight: 500 }}
          >
            Details
          </Button>
          <Button
            size="small"
            type="primary"
            icon={<SyncOutlined />}
            onClick={() => handleOpenDetails(record, 'actions')}
            style={{ borderRadius: 6, fontWeight: 600, background: '#1677FF' }}
          >
            Update
          </Button>
        </Space>
      ),
    },
  ];

  // Calculate visual step index
  const getFulfillmentStep = (st: string) => {
    const s = (st || '').toLowerCase();
    if (s.includes('delivered')) return 4;
    if (s.includes('out')) return 3;
    if (s.includes('ship') || s.includes('transit') || s.includes('dispatched')) return 3;
    if (s.includes('ready')) return 2;
    if (s.includes('production') || s.includes('process')) return 1;
    return 0;
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      {/* Top Header & Metrics Banner */}
      <Card
        style={{ background: '#FFFFFF', borderColor: '#E2E8F0', borderRadius: 10 }}
        styles={{ body: { padding: '20px 24px' } }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 12 }}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <FileTextOutlined style={{ color: '#1677FF', fontSize: 22 }} />
              <Title level={4} style={{ margin: 0, color: '#172B4D', fontWeight: 700 }}>
                Supplier Customer Fulfillment Orders Hub
              </Title>
              <Tag color="green" style={{ borderRadius: 10, fontWeight: 600 }}>
                Live Real-Time Synchronized
              </Tag>
            </div>
            <Paragraph type="secondary" style={{ margin: '4px 0 0 0', fontSize: 13, color: '#64748B' }}>
              Process and manage customer orders placed across your supply catalogue. Track escrow milestones and enter dispatch tracking numbers.
            </Paragraph>
          </div>
          <Space>
            <Button
              icon={<ReloadOutlined spin={loading} />}
              onClick={loadOrders}
              style={{ borderRadius: 6, fontWeight: 500 }}
            >
              Refresh Orders
            </Button>
          </Space>
        </div>

        <Divider style={{ margin: '16px 0' }} />

        {/* 4 Pipeline Stat Counters */}
        <Row gutter={[16, 16]}>
          <Col xs={12} sm={6}>
            <Statistic
              title={<Text type="secondary" style={{ fontSize: 12 }}>Total Received Orders</Text>}
              value={metrics.total}
              styles={{ content: { fontSize: 20, fontWeight: 700, color: '#172B4D' } }}
            />
          </Col>
          <Col xs={12} sm={6}>
            <Statistic
              title={<Text type="secondary" style={{ fontSize: 12 }}>Awaiting Dispatch</Text>}
              value={metrics.awaitingDispatch}
              styles={{ content: { fontSize: 20, fontWeight: 700, color: '#FAAD14' } }}
            />
          </Col>
          <Col xs={12} sm={6}>
            <Statistic
              title={<Text type="secondary" style={{ fontSize: 12 }}>In Transit / Carrier</Text>}
              value={metrics.inTransit}
              styles={{ content: { fontSize: 20, fontWeight: 700, color: '#1677FF' } }}
            />
          </Col>
          <Col xs={12} sm={6}>
            <Statistic
              title={<Text type="secondary" style={{ fontSize: 12 }}>Fulfilled & Released</Text>}
              value={metrics.delivered}
              styles={{ content: { fontSize: 20, fontWeight: 700, color: '#52C41A' } }}
            />
          </Col>
        </Row>
      </Card>

      {/* Filter and Search Controls */}
      <Card style={{ background: '#FFFFFF', borderColor: '#E2E8F0', borderRadius: 10 }} styles={{ body: { padding: '16px 20px' } }}>
        <Row gutter={[16, 16]} align="middle" justify="space-between">
          <Col xs={24} md={10}>
            <Input
              prefix={<SearchOutlined style={{ color: '#94A3B8' }} />}
              placeholder="Search by Order ID, Product, Customer Name, City..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              allowClear
              style={{ borderRadius: 6 }}
            />
          </Col>
          <Col xs={24} md={14} style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', flexWrap: 'wrap' }}>
            <Select
              value={statusFilter}
              onChange={setStatusFilter}
              style={{ width: 220 }}
              options={[
                { label: 'All Orders', value: 'ALL' },
                { label: 'Confirmed / New', value: 'confirmed' },
                { label: 'Processing', value: 'processing' },
                { label: 'Production / Preparation', value: 'production' },
                { label: 'Ready for Dispatch', value: 'ready_dispatch' },
                { label: 'Shipped (In Transit)', value: 'shipped' },
                { label: 'Out for Delivery', value: 'out_delivery' },
                { label: 'Delivered', value: 'delivered' },
                { label: 'Payment Pending', value: 'payment_pending' },
                { label: 'Cancelled', value: 'cancelled' },
              ]}
            />
            <Select
              value={sortBy}
              onChange={setSortBy}
              style={{ width: 180 }}
              options={[
                { label: 'Newest First', value: 'newest' },
                { label: 'Oldest First', value: 'oldest' },
                { label: 'Highest Order Value', value: 'highest_value' },
                { label: 'Lowest Order Value', value: 'lowest_value' },
              ]}
            />
          </Col>
        </Row>
      </Card>

      {/* Orders Table */}
      <Card style={{ background: '#FFFFFF', borderColor: '#E2E8F0', borderRadius: 10 }} styles={{ body: { padding: 0 } }}>
        <Table
          columns={columns}
          dataSource={filteredOrders}
          rowKey="id"
          pagination={{ pageSize: 8, showSizeChanger: true, pageSizeOptions: ['8', '16', '32'] }}
          loading={loading}
          locale={{ emptyText: 'No fulfillment orders match the current filter criteria.' }}
        />
      </Card>

      {/* Complete Order Details & Fulfillment Modal */}
      <Modal
        title={
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingRight: 24 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <BarcodeOutlined style={{ color: '#1677FF', fontSize: 20 }} />
              <div>
                <span style={{ fontWeight: 700, fontSize: 16 }}>Order Details: {activeOrderDetails?.order_number}</span>
                <span style={{ fontSize: 12, color: '#64748B', marginLeft: 8 }}>
                  Placed on {activeOrderDetails?.order_date}
                </span>
              </div>
            </div>
            <Tag color="cyan" style={{ fontWeight: 600, borderRadius: 10 }}>
              {activeOrderDetails?.payment_status || 'Escrow Secured'}
            </Tag>
          </div>
        }
        open={detailModalOpen}
        onCancel={() => setDetailModalOpen(false)}
        footer={null}
        width={850}
      >
        {activeOrderDetails && (
          <div>
            <Tabs
              activeKey={activeTabKey}
              onChange={setActiveTabKey}
              items={[
                {
                  key: 'summary',
                  label: <span><FileTextOutlined /> Order & Product Overview</span>,
                  children: (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 18, marginTop: 10 }}>
                      {/* Product Specifications Section */}
                      <Card
                        size="small"
                        title={<span style={{ fontWeight: 600 }}>Purchased Commercial Product</span>}
                        style={{ background: '#F8FAFC', borderColor: '#E2E8F0' }}
                      >
                        <Row gutter={16} align="middle">
                          <Col xs={24} sm={6} style={{ textAlign: 'center' }}>
                            <img
                              src={
                                activeOrderDetails.accepted_terms?.product_image ||
                                'https://images.unsplash.com/photo-1504307651254-35680f356dfd?auto=format&fit=crop&w=300&q=80'
                              }
                              alt={activeOrderDetails.product_name}
                              style={{ maxWidth: '100%', maxHeight: 110, objectFit: 'cover', borderRadius: 8 }}
                            />
                          </Col>
                          <Col xs={24} sm={18}>
                            <Title level={5} style={{ margin: 0, color: '#1E293B' }}>
                              {activeOrderDetails.product_name}
                            </Title>
                            <div style={{ fontSize: 12, color: '#64748B', marginTop: 2 }}>
                              Brand: <strong>{activeOrderDetails.accepted_terms?.brand || activeOrderDetails.merchant_name}</strong>
                              {activeOrderDetails.accepted_terms?.model && (
                                <span> &bull; Model: <strong>{activeOrderDetails.accepted_terms?.model}</strong></span>
                              )}
                            </div>

                            {/* Product Specs Badges */}
                            {activeOrderDetails.accepted_terms?.specifications &&
                              Object.keys(activeOrderDetails.accepted_terms.specifications).length > 0 && (
                                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 10 }}>
                                  {Object.entries(activeOrderDetails.accepted_terms.specifications).slice(0, 6).map(([k, v]) => (
                                    <Tag key={k} style={{ background: '#FFFFFF', border: '1px solid #CBD5E1', borderRadius: 4, fontSize: 11 }}>
                                      <Text type="secondary">{k}:</Text> <strong>{String(v)}</strong>
                                    </Tag>
                                  ))}
                                </div>
                              )}
                          </Col>
                        </Row>
                      </Card>

                      {/* Pricing Breakdown & Escrow Value */}
                      <Card size="small" title={<span style={{ fontWeight: 600 }}>Commercial Pricing & Escrow Ledger</span>}>
                        <Descriptions size="small" column={{ xs: 1, sm: 2, md: 3 }} bordered>
                          <Descriptions.Item label="Ordered Quantity">
                            <strong>{activeOrderDetails.quantity} {activeOrderDetails.accepted_terms?.unit || 'unit'}(s)</strong>
                          </Descriptions.Item>
                          <Descriptions.Item label="Unit Price">
                            ${Number(activeOrderDetails.accepted_terms?.unit_price || (activeOrderDetails.total_price / activeOrderDetails.quantity)).toFixed(2)}
                          </Descriptions.Item>
                          <Descriptions.Item label="Subtotal Amount">
                            ${Number(activeOrderDetails.total_price).toFixed(2)}
                          </Descriptions.Item>
                          <Descriptions.Item label="Applicable Taxes">
                            $0.00 (B2B Tax Exempt)
                          </Descriptions.Item>
                          <Descriptions.Item label="Freight / Logistics">
                            Included in Contract
                          </Descriptions.Item>
                          <Descriptions.Item label="Total Escrow Amount">
                            <strong style={{ color: '#059669', fontSize: 15 }}>
                              ${Number(activeOrderDetails.total_price).toFixed(2)} USD
                            </strong>
                          </Descriptions.Item>
                        </Descriptions>
                      </Card>

                      {/* Customer & Delivery Destination Information */}
                      <Row gutter={16}>
                        <Col xs={24} sm={12}>
                          <Card size="small" title={<span style={{ fontWeight: 600 }}><UserOutlined /> Customer Information</span>}>
                            <Descriptions size="small" column={1}>
                              <Descriptions.Item label="Customer Contact">
                                <strong>{activeOrderDetails.accepted_terms?.customer_name || 'Not provided'}</strong>
                              </Descriptions.Item>
                              <Descriptions.Item label="Contact Email">
                                {activeOrderDetails.accepted_terms?.customer_email || 'Email unavailable'}
                              </Descriptions.Item>
                              <Descriptions.Item label="Telephone">
                                {activeOrderDetails.accepted_terms?.customer_phone || 'Not provided'}
                              </Descriptions.Item>
                              <Descriptions.Item label="Procuring Entity">
                                {activeOrderDetails.accepted_terms?.customer_company || 'Not provided'}
                              </Descriptions.Item>
                            </Descriptions>
                          </Card>
                        </Col>
                        <Col xs={24} sm={12}>
                          <Card size="small" title={<span style={{ fontWeight: 600 }}><EnvironmentOutlined /> Delivery Destination</span>}>
                            <Descriptions size="small" column={1}>
                              <Descriptions.Item label="Freight Address">
                                <strong>{activeOrderDetails.accepted_terms?.delivery_address?.address || 'Address not provided'}</strong>
                              </Descriptions.Item>
                              <Descriptions.Item label="City & Postal Code">
                                {activeOrderDetails.accepted_terms?.delivery_address?.city || 'San Francisco'},{' '}
                                {activeOrderDetails.accepted_terms?.delivery_address?.state || 'CA'}{' '}
                                {activeOrderDetails.accepted_terms?.delivery_address?.postal_code || '94107'}
                              </Descriptions.Item>
                              <Descriptions.Item label="Dock Instructions">
                                {activeOrderDetails.accepted_terms?.delivery_address?.instructions || 'Standard freight dock receiving.'}
                              </Descriptions.Item>
                            </Descriptions>
                          </Card>
                        </Col>
                      </Row>

                      <div style={{ textAlign: 'right', marginTop: 10 }}>
                        <Button type="primary" icon={<SyncOutlined />} onClick={() => setActiveTabKey('actions')}>
                          Proceed to Update Fulfillment Stage &rarr;
                        </Button>
                      </div>
                    </div>
                  ),
                },
                {
                  key: 'timeline',
                  label: <span><ClockCircleOutlined /> Fulfillment Timeline & History</span>,
                  children: (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 20, marginTop: 14 }}>
                      {/* Visual Steps Tracker */}
                      <Card size="small">
                        <Steps
                          current={getFulfillmentStep(activeOrderDetails.order_status || activeOrderDetails.status)}
                          items={[
                            { title: 'Order Confirmed', description: 'Escrow Secured' },
                            { title: 'In Production', description: 'Batching / Packaging' },
                            { title: 'Ready for Dispatch', description: 'Inspected' },
                            { title: 'In Transit', description: activeOrderDetails.carrier || 'Logistics Provider' },
                            { title: 'Delivered', description: 'Destination Handover' },
                          ]}
                        />
                      </Card>

                      {/* Chronological Status Events */}
                      <Card
                        size="small"
                        title={<span style={{ fontWeight: 600 }}>Chronological Audit Trail & Status History</span>}
                      >
                        {activeOrderDetails.history && activeOrderDetails.history.length > 0 ? (
                          <Timeline
                            items={activeOrderDetails.history.map((h: any) => ({
                              color: h.new_status === 'Delivered' ? 'green' : 'blue',
                              children: (
                                <div>
                                  <div style={{ fontWeight: 600, color: '#1E293B' }}>
                                    {h.new_status} <Tag style={{ marginLeft: 6 }}>{h.actor_role || 'System'}</Tag>
                                  </div>
                                  <div style={{ fontSize: 12, color: '#475569' }}>
                                    {h.status_message || 'Status updated'}
                                  </div>
                                  <div style={{ fontSize: 11, color: '#94A3B8', marginTop: 2 }}>
                                    {new Date(h.created_at).toLocaleString()}
                                  </div>
                                </div>
                              ),
                            }))}
                          />
                        ) : (
                          <div style={{ color: '#64748B', fontSize: 13, padding: 12 }}>
                            Initial confirmation registered. Subsequent fulfillment stages will log chronological timestamps here.
                          </div>
                        )}
                      </Card>
                    </div>
                  ),
                },
                {
                  key: 'actions',
                  label: <span><SyncOutlined /> Update Fulfillment Stage</span>,
                  children: (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, marginTop: 14 }}>
                      <Alert
                        type="info"
                        showIcon
                        title="Real-time Platform Synchronization"
                        description="Any milestone update and logistics tracking number saved here immediately updates the Customer dashboard via Supabase Realtime."
                      />

                      <Form form={form} layout="vertical" onFinish={handleUpdateStatus}>
                        <Form.Item
                          name="status"
                          label="Fulfillment Stage Transition"
                          rules={[{ required: true, message: 'Please select a fulfillment stage' }]}
                        >
                          <Select
                            options={[
                              { label: 'Confirmed (Order Confirmed in Escrow)', value: 'Confirmed' },
                              { label: 'Processing (Inventory Allocation / Batching)', value: 'Processing' },
                              { label: 'Production / Preparation (Manufacturing & Packaging)', value: 'Production / Preparation' },
                              { label: 'Ready for Dispatch (Inspected & Staged for Carrier)', value: 'Ready for Dispatch' },
                              { label: 'Shipped (Dispatched with Freight Carrier)', value: 'Shipped' },
                              { label: 'Out for Delivery (Local Distribution Hub)', value: 'Out for Delivery' },
                              { label: 'Delivered (Destination Handover Completed)', value: 'Delivered' },
                              { label: 'Cancelled', value: 'Cancelled' },
                            ]}
                          />
                        </Form.Item>

                        <Row gutter={16}>
                          <Col xs={24} sm={12}>
                            <Form.Item name="carrier" label="Logistics Carrier">
                              <Select
                                options={[
                                  { label: 'FedEx Commercial Freight', value: 'FedEx Commercial Freight' },
                                  { label: 'DHL Express Global Logistics', value: 'DHL Express Global Logistics' },
                                  { label: 'UPS Supply Chain Solutions', value: 'UPS Supply Chain Solutions' },
                                  { label: 'Direct Merchant Fleet', value: 'Direct Merchant Fleet' },
                                  { label: 'Maersk Regional Freight', value: 'Maersk Regional Freight' },
                                ]}
                              />
                            </Form.Item>
                          </Col>
                          <Col xs={24} sm={12}>
                            <Form.Item name="tracking_number" label="Waybill / Tracking Reference Number">
                              <Input placeholder="e.g. FDX-984021-US" />
                            </Form.Item>
                          </Col>
                        </Row>

                        <Form.Item name="remarks" label="Merchant Dispatch Remarks / Notes">
                          <Input.TextArea
                            rows={3}
                            placeholder="Enter notes on cargo packaging, pallet count, driver contact or dispatch handover details..."
                          />
                        </Form.Item>

                        <div style={{ textAlign: 'right', marginTop: 10 }}>
                          <Space>
                            <Button onClick={() => setDetailModalOpen(false)}>Cancel</Button>
                            <Button
                              type="primary"
                              htmlType="submit"
                              loading={submittingStatus}
                              style={{ background: '#1677FF', fontWeight: 600 }}
                            >
                              Save & Push Live Update
                            </Button>
                          </Space>
                        </div>
                      </Form>
                    </div>
                  ),
                },
              ]}
            />
          </div>
        )}
      </Modal>
    </div>
  );
};

export default MerchantOrders;
