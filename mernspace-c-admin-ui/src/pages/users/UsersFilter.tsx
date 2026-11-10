import { Card, Col, Form, Input, Row, Select } from 'antd';

type UsersFilterProps = {
    children?: React.ReactNode;
};
const UsersFilter = ({ children }: UsersFilterProps) => {
    return (
        <Card>
            <Row justify="space-between">
                <Col span={16}>
                    <Row gutter={20}>
                        <Col span={8}>
                            <Form.Item name="q">
                                <Input.Search allowClear={true} placeholder="Search" />
                            </Form.Item>
                        </Col>
                        <Col span={8}>
                            <Form.Item name="role">
                                <Select
                                    style={{ width: '100%' }}
                                    allowClear={true}
                                    placeholder="Select role">
                                    <Select.Option value="admin">Admin</Select.Option>
                                    <Select.Option value="manager">Manager</Select.Option>
                                    <Select.Option value="customer">Customer</Select.Option>
                                </Select>
                            </Form.Item>
                        </Col>
                        {/* <Col span={8}>
                            <Select
                                style={{ width: '100%' }}
                                placeholder="Status"
                                allowClear={true}
                                onChange={(selectedItem) =>
                                    onFilterChange('statusFilter', selectedItem)
                                }>
                                <Select.Option value="ban">Ban</Select.Option>
                                <Select.Option value="active">Active</Select.Option>
                            </Select>
                        </Col> */}
                    </Row>
                </Col>
                <Col span={8} style={{ display: 'flex', justifyContent: 'end' }}>
                    {children}
                </Col>
            </Row>
        </Card>
    );
};

export default UsersFilter;
