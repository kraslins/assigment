drop table if exists order_log cascade;
drop table if exists order_items cascade;
drop table if exists orders cascade;
drop table if exists products cascade;
drop table if exists customers cascade;

create table customers (
    customer_id serial primary key,
    full_name varchar(100) not null,
    email varchar(100) unique not null,
    balance numeric(10,2) default 0
);

create table products (
    product_id serial primary key,
    product_name varchar(100) not null,
    price numeric(10,2) not null,
    stock_quantity int not null
);

create table orders (
    order_id serial primary key,
    customer_id int references customers(customer_id),
    order_date timestamp default current_timestamp,
    total_amount numeric(10,2) default 0
);

create table order_items (
    order_item_id serial primary key,
    order_id int references orders(order_id),
    product_id int references products(product_id),
    quantity int not null,
    price numeric(10,2) not null
);

create table order_log (
    log_id serial primary key,
    order_id int,
    customer_id int,
    action varchar(50),
    log_date timestamp default current_timestamp
);

create or replace function calculate_order_total(p_order_id int)
returns numeric(10,2)
language plpgsql
as $$
declare
    v_total numeric(10,2);
begin
    select coalesce(sum(quantity * price), 0)
    into v_total
    from order_items
    where order_id = p_order_id;

    return v_total;
end;
$$;

create or replace procedure create_order(p_customer_id int)
language plpgsql
as $$
declare
    v_exists int;
begin
    select count(*) into v_exists from customers where customer_id = p_customer_id;
    if v_exists = 0 then
        raise notice 'customer does not exist';
        return;
    end if;

    insert into orders (customer_id, order_date, total_amount)
    values (p_customer_id, current_timestamp, 0);
end;
$$;

create or replace procedure add_product_to_order(
    p_order_id int,
    p_product_id int,
    p_quantity int
)
language plpgsql
as $$
declare
    v_price numeric(10,2);
    v_stock int;
begin
    if p_quantity <= 0 then
        raise exception 'invalid quantity';
    end if;

    select price, stock_quantity
    into v_price, v_stock
    from products
    where product_id = p_product_id;

    if v_price is null then
        raise exception 'product not found';
    end if;

    if v_stock < p_quantity then
        raise exception 'not enough stock';
    end if;

    insert into order_items (order_id, product_id, quantity, price)
    values (p_order_id, p_product_id, p_quantity, v_price);

    update products
    set stock_quantity = stock_quantity - p_quantity
    where product_id = p_product_id;
end;
$$;

create or replace function trg_update_order_total()
returns trigger
language plpgsql
as $$
begin
    if tg_op = 'DELETE' then
        update orders
        set total_amount = calculate_order_total(old.order_id)
        where order_id = old.order_id;
        return old;
    else
        update orders
        set total_amount = calculate_order_total(new.order_id)
        where order_id = new.order_id;
        return new;
    end if;
end;
$$;

drop trigger if exists trg_order_items_after_change on order_items;

create trigger trg_order_items_after_change
after insert or update or delete on order_items
for each row
execute function trg_update_order_total();

create or replace function trg_log_new_order()
returns trigger
language plpgsql
as $$
begin
    insert into order_log (order_id, customer_id, action, log_date)
    values (new.order_id, new.customer_id, 'ORDER_CREATED', current_timestamp);
    return new;
end;
$$;

drop trigger if exists trg_orders_after_insert on orders;

create trigger trg_orders_after_insert
after insert on orders
for each row
execute function trg_log_new_order();

insert into customers (full_name, email, balance) values
    ('John Smith', 'john.smith@example.com', 150.00),
    ('Anna Brown', 'anna.brown@example.com', 300.00);

insert into products (product_name, price, stock_quantity) values
    ('Laptop', 1200.00, 10),
    ('Mouse', 25.00, 100),
    ('Keyboard', 70.00, 50);

select * from customers;
select * from products;

call create_order(1);
select * from orders;

call create_order(999);
select * from orders;

call add_product_to_order(1, 1, 1);
call add_product_to_order(1, 2, 2);

select * from order_items where order_id = 1;
select order_id, total_amount from orders where order_id = 1;
select calculate_order_total(1);

select product_id, product_name, stock_quantity from products where product_id in (1, 2);
select * from order_log;

update order_items set quantity = 3 where order_id = 1 and product_id = 2;
select order_id, total_amount from orders where order_id = 1;

delete from order_items where order_id = 1 and product_id = 2;
select order_id, total_amount from orders where order_id = 1;
