--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA topology;


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


SET search_path = public, pg_catalog;

--
-- Name: update_group_count(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_group_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
            DECLARE
              is_test boolean;
            BEGIN
              -- Contact being added to group
              IF TG_OP = 'INSERT' THEN
                -- Find out if this is a test contact
                SELECT contacts_contact.is_test INTO STRICT is_test FROM contacts_contact WHERE id=NEW.contact_id;

                -- If not
                if not is_test THEN
                  -- Increment our group count
                  UPDATE contacts_contactgroup SET count=count+1 WHERE id=NEW.contactgroup_id;
                END IF;

              -- Contact being removed from a group
              ELSIF TG_OP = 'DELETE' THEN
                -- Find out if this is a test contact
                SELECT contacts_contact.is_test INTO STRICT is_test FROM contacts_contact WHERE id=OLD.contact_id;

                -- If not
                if not is_test THEN
                  -- Decrement our group count
                  UPDATE contacts_contactgroup SET count=count-1 WHERE id=OLD.contactgroup_id;
                END IF;

              -- Table being cleared, reset all counts
              ELSIF TG_OP = 'TRUNCATE' THEN
                UPDATE contacts_contactgroup SET count=0;
              END IF;

              RETURN NEW;
            END;
            $$;


--
-- Name: update_label_count(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_label_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
            DECLARE
              is_included boolean;
            BEGIN
              -- label applied to message
              IF TG_TABLE_NAME = 'msgs_msg_labels' AND TG_OP = 'INSERT' THEN
                -- is this message visible and non-test?
                SELECT (msgs_msg.visibility = 'V' AND NOT contacts_contact.is_test) INTO STRICT is_included
                FROM msgs_msg
                INNER JOIN contacts_contact ON contacts_contact.id = msgs_msg.contact_id
                WHERE msgs_msg.id = NEW.msg_id;

                IF is_included THEN
                  UPDATE msgs_label SET visible_count = visible_count + 1 WHERE id=NEW.label_id;
                END IF;

              -- label removed from message
              ELSIF TG_TABLE_NAME = 'msgs_msg_labels' AND TG_OP = 'DELETE' THEN
                -- is this message visible and non-test?
                SELECT (msgs_msg.visibility = 'V' AND NOT contacts_contact.is_test) INTO STRICT is_included
                FROM msgs_msg
                INNER JOIN contacts_contact ON contacts_contact.id = msgs_msg.contact_id
                WHERE msgs_msg.id = OLD.msg_id;

                IF is_included THEN
                  UPDATE msgs_label SET visible_count = visible_count - 1 WHERE id=OLD.label_id;
                END IF;

              -- no more labels for any messages
              ELSIF TG_TABLE_NAME = 'msgs_msg_labels' AND TG_OP = 'TRUNCATE' THEN
                UPDATE msgs_label SET visible_count = 0;

              -- message visibility may have changed
              ELSIF TG_TABLE_NAME = 'msgs_msg' AND TG_OP = 'UPDATE' THEN
                -- is being archived (i.e. no longer included)
                IF OLD.visibility = 'V' AND NEW.visibility = 'A' THEN
                  UPDATE msgs_label SET visible_count = msgs_label.visible_count - 1
                  FROM msgs_msg_labels
                  WHERE msgs_msg_labels.label_id = msgs_label.id AND msgs_msg_labels.msg_id = NEW.id;
                END IF;
                -- is being restored (i.e. now included)
                IF OLD.visibility = 'A' AND NEW.visibility = 'V' THEN
                  UPDATE msgs_label SET visible_count = msgs_label.visible_count + 1
                  FROM msgs_msg_labels
                  WHERE msgs_msg_labels.label_id = msgs_label.id AND msgs_msg_labels.msg_id = NEW.id;
                END IF;
              END IF;

              RETURN NULL;
            END;
            $$;


--
-- Name: update_topup_used(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_topup_used() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
            BEGIN
              -- Msg is being created
              IF TG_OP = 'INSERT' THEN
                -- If we have a topup, increment our # of used credits
                IF NEW.topup_id IS NOT NULL THEN
                  UPDATE orgs_topup SET used=used+1 where id=NEW.topup_id;
                END IF;

              -- Msg is being updated
              ELSIF TG_OP = 'UPDATE' THEN
                -- If the topup has changed
                IF NEW.topup_id IS DISTINCT FROM OLD.topup_id THEN
                  -- If our old topup wasn't null then decrement our used credits on it
                  IF OLD.topup_id IS NOT NULL THEN
                    UPDATE orgs_topup SET used=used-1 where id=OLD.topup_id;
                  END IF;

                  -- if our new topup isn't null, then increment our used credits on it
                  IF NEW.topup_id IS NOT NULL THEN
                    UPDATE orgs_topup SET used=used+1 where id=NEW.topup_id;
                  END IF;
                END IF;

              -- Msg is being deleted
              ELSIF TG_OP = 'DELETE' THEN
                -- Remove a used credit if this Msg had one assigned
                IF OLD.topup_id IS NOT NULL THEN
                  UPDATE orgs_topup SET used=used-1 WHERE id=OLD.topup_id;
                END IF;

              -- Msgs table is being truncated
              ELSIF TG_OP = 'TRUNCATE' THEN
                -- Clear all used credits
                UPDATE orgs_topup SET used=0;

              END IF;

              RETURN NEW;
            END;
            $$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: api_apitoken; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE api_apitoken (
    key character varying(40) NOT NULL,
    created timestamp with time zone NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: api_webhookevent; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE api_webhookevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    status character varying(1) NOT NULL,
    event character varying(16) NOT NULL,
    data text NOT NULL,
    try_count integer NOT NULL,
    next_attempt timestamp with time zone,
    action character varying(8) NOT NULL,
    channel_id integer,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: api_webhookevent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE api_webhookevent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_webhookevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE api_webhookevent_id_seq OWNED BY api_webhookevent.id;


--
-- Name: api_webhookresult; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE api_webhookresult (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    url text,
    data text,
    status_code integer NOT NULL,
    message character varying(255) NOT NULL,
    body text,
    created_by_id integer NOT NULL,
    event_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    request text
);


--
-- Name: api_webhookresult_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE api_webhookresult_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_webhookresult_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE api_webhookresult_id_seq OWNED BY api_webhookresult.id;


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_group (
    id integer NOT NULL,
    name character varying(80) NOT NULL
);


--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_group_id_seq OWNED BY auth_group.id;


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_group_permissions (
    id integer NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_group_permissions_id_seq OWNED BY auth_group_permissions.id;


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_permission (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_permission_id_seq OWNED BY auth_permission.id;


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone NOT NULL,
    is_superuser boolean NOT NULL,
    username character varying(30) NOT NULL,
    first_name character varying(30) NOT NULL,
    last_name character varying(30) NOT NULL,
    email character varying(75) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_user_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_user_groups_id_seq OWNED BY auth_user_groups.id;


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_user_id_seq OWNED BY auth_user.id;


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE auth_user_user_permissions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE auth_user_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE auth_user_user_permissions_id_seq OWNED BY auth_user_user_permissions.id;


--
-- Name: authtoken_token; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE authtoken_token (
    key character varying(40) NOT NULL,
    created timestamp with time zone NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: campaigns_campaign; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE campaigns_campaign (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(255) NOT NULL,
    is_archived boolean NOT NULL,
    created_by_id integer NOT NULL,
    group_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    uuid character varying(36) NOT NULL
);


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE campaigns_campaign_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE campaigns_campaign_id_seq OWNED BY campaigns_campaign.id;


--
-- Name: campaigns_campaignevent; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE campaigns_campaignevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    "offset" integer NOT NULL,
    unit character varying(1) NOT NULL,
    event_type character varying(1) NOT NULL,
    message text,
    delivery_hour integer NOT NULL,
    campaign_id integer NOT NULL,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    relative_to_id integer NOT NULL,
    uuid character varying(36) NOT NULL
);


--
-- Name: campaigns_campaignevent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE campaigns_campaignevent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_campaignevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE campaigns_campaignevent_id_seq OWNED BY campaigns_campaignevent.id;


--
-- Name: campaigns_eventfire; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE campaigns_eventfire (
    id integer NOT NULL,
    scheduled timestamp with time zone NOT NULL,
    fired timestamp with time zone,
    contact_id integer NOT NULL,
    event_id integer NOT NULL
);


--
-- Name: campaigns_eventfire_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE campaigns_eventfire_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_eventfire_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE campaigns_eventfire_id_seq OWNED BY campaigns_eventfire.id;


--
-- Name: celery_taskmeta; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE celery_taskmeta (
    id integer NOT NULL,
    task_id character varying(255) NOT NULL,
    status character varying(50) NOT NULL,
    result text,
    date_done timestamp with time zone NOT NULL,
    traceback text,
    hidden boolean NOT NULL,
    meta text
);


--
-- Name: celery_taskmeta_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE celery_taskmeta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: celery_taskmeta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE celery_taskmeta_id_seq OWNED BY celery_taskmeta.id;


--
-- Name: celery_tasksetmeta; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE celery_tasksetmeta (
    id integer NOT NULL,
    taskset_id character varying(255) NOT NULL,
    result text NOT NULL,
    date_done timestamp with time zone NOT NULL,
    hidden boolean NOT NULL
);


--
-- Name: celery_tasksetmeta_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE celery_tasksetmeta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: celery_tasksetmeta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE celery_tasksetmeta_id_seq OWNED BY celery_tasksetmeta.id;


--
-- Name: channels_alert; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_alert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    alert_type character varying(1) NOT NULL,
    ended_on timestamp with time zone,
    host character varying(32) NOT NULL,
    channel_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    sync_event_id integer
);


--
-- Name: channels_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_alert_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_alert_id_seq OWNED BY channels_alert.id;


--
-- Name: channels_channel; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_channel (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    channel_type character varying(3) NOT NULL,
    name character varying(64),
    address character varying(16),
    country character varying(2),
    gcm_id character varying(255),
    uuid character varying(36),
    claim_code character varying(16),
    secret character varying(64),
    last_seen timestamp with time zone NOT NULL,
    device character varying(255),
    os character varying(255),
    alert_email character varying(75),
    config text,
    role character varying(4) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer,
    parent_id integer,
    bod text
);


--
-- Name: channels_channel_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_channel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_channel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_channel_id_seq OWNED BY channels_channel.id;


--
-- Name: channels_channellog; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_channellog (
    id integer NOT NULL,
    description character varying(255) NOT NULL,
    is_error boolean NOT NULL,
    url text,
    method character varying(16),
    request text,
    response text,
    response_status integer,
    created_on timestamp with time zone NOT NULL,
    msg_id integer NOT NULL
);


--
-- Name: channels_channellog_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_channellog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_channellog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_channellog_id_seq OWNED BY channels_channellog.id;


--
-- Name: channels_syncevent; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE channels_syncevent (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    power_source character varying(64) NOT NULL,
    power_status character varying(64) NOT NULL,
    power_level integer NOT NULL,
    network_type character varying(128) NOT NULL,
    lifetime integer,
    pending_message_count integer NOT NULL,
    retry_message_count integer NOT NULL,
    incoming_command_count integer NOT NULL,
    outgoing_command_count integer NOT NULL,
    channel_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: channels_syncevent_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE channels_syncevent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_syncevent_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE channels_syncevent_id_seq OWNED BY channels_syncevent.id;


--
-- Name: contacts_contact; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contact (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128),
    uuid character varying(36) NOT NULL,
    is_blocked boolean NOT NULL,
    is_test boolean NOT NULL,
    language character varying(3),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    is_failed boolean NOT NULL
);


--
-- Name: contacts_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contact_id_seq OWNED BY contacts_contact.id;


--
-- Name: contacts_contactfield; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contactfield (
    id integer NOT NULL,
    label character varying(36) NOT NULL,
    key character varying(36) NOT NULL,
    is_active boolean NOT NULL,
    value_type character varying(1) NOT NULL,
    show_in_table boolean NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: contacts_contactfield_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactfield_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactfield_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactfield_id_seq OWNED BY contacts_contactfield.id;


--
-- Name: contacts_contactgroup; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contactgroup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(64) NOT NULL,
    query text,
    created_by_id integer NOT NULL,
    import_task_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    count integer NOT NULL,
    group_type character varying(1) NOT NULL
);


--
-- Name: contacts_contactgroup_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contactgroup_contacts (
    id integer NOT NULL,
    contactgroup_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: contacts_contactgroup_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactgroup_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactgroup_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactgroup_contacts_id_seq OWNED BY contacts_contactgroup_contacts.id;


--
-- Name: contacts_contactgroup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactgroup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactgroup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactgroup_id_seq OWNED BY contacts_contactgroup.id;


--
-- Name: contacts_contactgroup_query_fields; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contactgroup_query_fields (
    id integer NOT NULL,
    contactgroup_id integer NOT NULL,
    contactfield_id integer NOT NULL
);


--
-- Name: contacts_contactgroup_query_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contactgroup_query_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contactgroup_query_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contactgroup_query_fields_id_seq OWNED BY contacts_contactgroup_query_fields.id;


--
-- Name: contacts_contacturn; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_contacturn (
    id integer NOT NULL,
    urn character varying(255) NOT NULL,
    path character varying(255) NOT NULL,
    scheme character varying(128) NOT NULL,
    priority integer NOT NULL,
    channel_id integer,
    contact_id integer,
    org_id integer NOT NULL
);


--
-- Name: contacts_contacturn_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_contacturn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_contacturn_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_contacturn_id_seq OWNED BY contacts_contacturn.id;


--
-- Name: contacts_exportcontactstask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE contacts_exportcontactstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    host character varying(32) NOT NULL,
    task_id character varying(64),
    created_by_id integer NOT NULL,
    group_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: contacts_exportcontactstask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE contacts_exportcontactstask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_exportcontactstask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE contacts_exportcontactstask_id_seq OWNED BY contacts_exportcontactstask.id;


--
-- Name: csv_imports_importtask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE csv_imports_importtask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    csv_file character varying(100) NOT NULL,
    model_class character varying(255) NOT NULL,
    import_params text,
    import_log text NOT NULL,
    import_results text,
    task_id character varying(64)
);


--
-- Name: csv_imports_importtask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE csv_imports_importtask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: csv_imports_importtask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE csv_imports_importtask_id_seq OWNED BY csv_imports_importtask.id;


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE django_content_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_content_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE django_content_type_id_seq OWNED BY django_content_type.id;


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE django_migrations (
    id integer NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE django_migrations_id_seq OWNED BY django_migrations.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


--
-- Name: django_site; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE django_site (
    id integer NOT NULL,
    domain character varying(100) NOT NULL,
    name character varying(50) NOT NULL
);


--
-- Name: django_site_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE django_site_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_site_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE django_site_id_seq OWNED BY django_site.id;


--
-- Name: djcelery_crontabschedule; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_crontabschedule (
    id integer NOT NULL,
    minute character varying(64) NOT NULL,
    hour character varying(64) NOT NULL,
    day_of_week character varying(64) NOT NULL,
    day_of_month character varying(64) NOT NULL,
    month_of_year character varying(64) NOT NULL
);


--
-- Name: djcelery_crontabschedule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_crontabschedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_crontabschedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_crontabschedule_id_seq OWNED BY djcelery_crontabschedule.id;


--
-- Name: djcelery_intervalschedule; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_intervalschedule (
    id integer NOT NULL,
    every integer NOT NULL,
    period character varying(24) NOT NULL
);


--
-- Name: djcelery_intervalschedule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_intervalschedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_intervalschedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_intervalschedule_id_seq OWNED BY djcelery_intervalschedule.id;


--
-- Name: djcelery_periodictask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_periodictask (
    id integer NOT NULL,
    name character varying(200) NOT NULL,
    task character varying(200) NOT NULL,
    interval_id integer,
    crontab_id integer,
    args text NOT NULL,
    kwargs text NOT NULL,
    queue character varying(200),
    exchange character varying(200),
    routing_key character varying(200),
    expires timestamp with time zone,
    enabled boolean NOT NULL,
    last_run_at timestamp with time zone,
    total_run_count integer NOT NULL,
    date_changed timestamp with time zone NOT NULL,
    description text NOT NULL,
    CONSTRAINT djcelery_periodictask_total_run_count_check CHECK ((total_run_count >= 0))
);


--
-- Name: djcelery_periodictask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_periodictask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_periodictask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_periodictask_id_seq OWNED BY djcelery_periodictask.id;


--
-- Name: djcelery_periodictasks; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_periodictasks (
    ident smallint NOT NULL,
    last_update timestamp with time zone NOT NULL
);


--
-- Name: djcelery_taskstate; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_taskstate (
    id integer NOT NULL,
    state character varying(64) NOT NULL,
    task_id character varying(36) NOT NULL,
    name character varying(200),
    tstamp timestamp with time zone NOT NULL,
    args text,
    kwargs text,
    eta timestamp with time zone,
    expires timestamp with time zone,
    result text,
    traceback text,
    runtime double precision,
    retries integer NOT NULL,
    worker_id integer,
    hidden boolean NOT NULL
);


--
-- Name: djcelery_taskstate_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_taskstate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_taskstate_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_taskstate_id_seq OWNED BY djcelery_taskstate.id;


--
-- Name: djcelery_workerstate; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE djcelery_workerstate (
    id integer NOT NULL,
    hostname character varying(255) NOT NULL,
    last_heartbeat timestamp with time zone
);


--
-- Name: djcelery_workerstate_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE djcelery_workerstate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: djcelery_workerstate_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE djcelery_workerstate_id_seq OWNED BY djcelery_workerstate.id;


--
-- Name: flows_actionlog; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_actionlog (
    id integer NOT NULL,
    text text NOT NULL,
    created_on timestamp with time zone NOT NULL,
    run_id integer NOT NULL
);


--
-- Name: flows_actionlog_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_actionlog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_actionlog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_actionlog_id_seq OWNED BY flows_actionlog.id;


--
-- Name: flows_actionset; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_actionset (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    actions text NOT NULL,
    x integer NOT NULL,
    y integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    flow_id integer NOT NULL,
    destination character varying(36),
    destination_type character varying(1)
);


--
-- Name: flows_actionset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_actionset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_actionset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_actionset_id_seq OWNED BY flows_actionset.id;


--
-- Name: flows_exportflowresultstask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_exportflowresultstask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    host character varying(32) NOT NULL,
    task_id character varying(64),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: flows_exportflowresultstask_flows; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_exportflowresultstask_flows (
    id integer NOT NULL,
    exportflowresultstask_id integer NOT NULL,
    flow_id integer NOT NULL
);


--
-- Name: flows_exportflowresultstask_flows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_exportflowresultstask_flows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_exportflowresultstask_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_exportflowresultstask_flows_id_seq OWNED BY flows_exportflowresultstask_flows.id;


--
-- Name: flows_exportflowresultstask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_exportflowresultstask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_exportflowresultstask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_exportflowresultstask_id_seq OWNED BY flows_exportflowresultstask.id;


--
-- Name: flows_flow; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flow (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(64) NOT NULL,
    entry_uuid character varying(36),
    entry_type character varying(1),
    is_archived boolean NOT NULL,
    flow_type character varying(1) NOT NULL,
    metadata text,
    expires_after_minutes integer NOT NULL,
    ignore_triggers boolean NOT NULL,
    saved_on timestamp with time zone NOT NULL,
    base_language character varying(3),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    saved_by_id integer NOT NULL,
    uuid character varying(36) NOT NULL
);


--
-- Name: flows_flow_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flow_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flow_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flow_id_seq OWNED BY flows_flow.id;


--
-- Name: flows_flow_labels; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flow_labels (
    id integer NOT NULL,
    flow_id integer NOT NULL,
    flowlabel_id integer NOT NULL
);


--
-- Name: flows_flow_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flow_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flow_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flow_labels_id_seq OWNED BY flows_flow_labels.id;


--
-- Name: flows_flowlabel; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowlabel (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    org_id integer NOT NULL,
    parent_id integer
);


--
-- Name: flows_flowlabel_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowlabel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowlabel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowlabel_id_seq OWNED BY flows_flowlabel.id;


--
-- Name: flows_flowrun; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowrun (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    fields text,
    created_on timestamp with time zone NOT NULL,
    expires_on timestamp with time zone,
    expired_on timestamp with time zone,
    call_id integer,
    contact_id integer NOT NULL,
    flow_id integer NOT NULL,
    start_id integer
);


--
-- Name: flows_flowrun_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowrun_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowrun_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowrun_id_seq OWNED BY flows_flowrun.id;


--
-- Name: flows_flowstart; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowstart (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    restart_participants boolean NOT NULL,
    contact_count integer NOT NULL,
    status character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: flows_flowstart_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowstart_contacts (
    id integer NOT NULL,
    flowstart_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: flows_flowstart_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstart_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstart_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstart_contacts_id_seq OWNED BY flows_flowstart_contacts.id;


--
-- Name: flows_flowstart_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowstart_groups (
    id integer NOT NULL,
    flowstart_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: flows_flowstart_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstart_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstart_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstart_groups_id_seq OWNED BY flows_flowstart_groups.id;


--
-- Name: flows_flowstart_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstart_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstart_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstart_id_seq OWNED BY flows_flowstart.id;


--
-- Name: flows_flowstep; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowstep (
    id integer NOT NULL,
    step_type character varying(1) NOT NULL,
    step_uuid character varying(36) NOT NULL,
    rule_uuid character varying(36),
    rule_category character varying(36),
    rule_value character varying(640),
    rule_decimal_value numeric(36,8),
    next_uuid character varying(36),
    arrived_on timestamp with time zone NOT NULL,
    left_on timestamp with time zone,
    contact_id integer NOT NULL,
    run_id integer NOT NULL
);


--
-- Name: flows_flowstep_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstep_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstep_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstep_id_seq OWNED BY flows_flowstep.id;


--
-- Name: flows_flowstep_messages; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowstep_messages (
    id integer NOT NULL,
    flowstep_id integer NOT NULL,
    msg_id integer NOT NULL
);


--
-- Name: flows_flowstep_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowstep_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowstep_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowstep_messages_id_seq OWNED BY flows_flowstep_messages.id;


--
-- Name: flows_flowversion; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_flowversion (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    definition text NOT NULL,
    created_by_id integer NOT NULL,
    flow_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: flows_flowversion_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_flowversion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_flowversion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_flowversion_id_seq OWNED BY flows_flowversion.id;


--
-- Name: flows_ruleset; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE flows_ruleset (
    id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    label character varying(64),
    operand character varying(128),
    webhook_url character varying(255),
    webhook_action character varying(8),
    rules text NOT NULL,
    finished_key character varying(1),
    value_type character varying(1) NOT NULL,
    response_type character varying(1) NOT NULL,
    x integer NOT NULL,
    y integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    flow_id integer NOT NULL
);


--
-- Name: flows_ruleset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE flows_ruleset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_ruleset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE flows_ruleset_id_seq OWNED BY flows_ruleset.id;


--
-- Name: guardian_groupobjectpermission; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE guardian_groupobjectpermission (
    id integer NOT NULL,
    permission_id integer NOT NULL,
    content_type_id integer NOT NULL,
    object_pk character varying(255) NOT NULL,
    group_id integer NOT NULL
);


--
-- Name: guardian_groupobjectpermission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE guardian_groupobjectpermission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: guardian_groupobjectpermission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE guardian_groupobjectpermission_id_seq OWNED BY guardian_groupobjectpermission.id;


--
-- Name: guardian_userobjectpermission; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE guardian_userobjectpermission (
    id integer NOT NULL,
    permission_id integer NOT NULL,
    content_type_id integer NOT NULL,
    object_pk character varying(255) NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: guardian_userobjectpermission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE guardian_userobjectpermission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: guardian_userobjectpermission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE guardian_userobjectpermission_id_seq OWNED BY guardian_userobjectpermission.id;


--
-- Name: ivr_ivrcall; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE ivr_ivrcall (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    external_id character varying(255) NOT NULL,
    status character varying(1) NOT NULL,
    direction character varying(1) NOT NULL,
    started_on timestamp with time zone,
    ended_on timestamp with time zone,
    call_type character varying(1) NOT NULL,
    duration integer,
    channel_id integer NOT NULL,
    contact_id integer NOT NULL,
    created_by_id integer NOT NULL,
    flow_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    contact_urn_id integer NOT NULL
);


--
-- Name: ivr_ivrcall_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE ivr_ivrcall_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ivr_ivrcall_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE ivr_ivrcall_id_seq OWNED BY ivr_ivrcall.id;


--
-- Name: locations_adminboundary; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE locations_adminboundary (
    id integer NOT NULL,
    osm_id character varying(15) NOT NULL,
    name character varying(128) NOT NULL,
    level integer NOT NULL,
    geometry geometry(MultiPolygon,4326),
    simplified_geometry geometry(MultiPolygon,4326),
    parent_id integer
);


--
-- Name: locations_adminboundary_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE locations_adminboundary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations_adminboundary_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE locations_adminboundary_id_seq OWNED BY locations_adminboundary.id;


--
-- Name: locations_boundaryalias; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE locations_boundaryalias (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    boundary_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: locations_boundaryalias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE locations_boundaryalias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations_boundaryalias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE locations_boundaryalias_id_seq OWNED BY locations_boundaryalias.id;


--
-- Name: msgs_broadcast; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_broadcast (
    id integer NOT NULL,
    recipient_count integer,
    text text NOT NULL,
    status character varying(1) NOT NULL,
    language_dict text,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    parent_id integer,
    schedule_id integer,
    channel_id integer
);


--
-- Name: msgs_broadcast_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_broadcast_contacts (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: msgs_broadcast_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_contacts_id_seq OWNED BY msgs_broadcast_contacts.id;


--
-- Name: msgs_broadcast_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_broadcast_groups (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: msgs_broadcast_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_groups_id_seq OWNED BY msgs_broadcast_groups.id;


--
-- Name: msgs_broadcast_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_id_seq OWNED BY msgs_broadcast.id;


--
-- Name: msgs_broadcast_urns; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_broadcast_urns (
    id integer NOT NULL,
    broadcast_id integer NOT NULL,
    contacturn_id integer NOT NULL
);


--
-- Name: msgs_broadcast_urns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_broadcast_urns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_broadcast_urns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_broadcast_urns_id_seq OWNED BY msgs_broadcast_urns.id;


--
-- Name: msgs_call; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_call (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    "time" timestamp with time zone NOT NULL,
    duration integer NOT NULL,
    call_type character varying(16) NOT NULL,
    channel_id integer,
    contact_id integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: msgs_call_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_call_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_call_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_call_id_seq OWNED BY msgs_call.id;


--
-- Name: msgs_exportmessagestask; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_exportmessagestask (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    start_date date,
    end_date date,
    host character varying(32) NOT NULL,
    task_id character varying(64),
    created_by_id integer NOT NULL,
    label_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: msgs_exportmessagestask_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_exportmessagestask_groups (
    id integer NOT NULL,
    exportmessagestask_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: msgs_exportmessagestask_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_exportmessagestask_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_exportmessagestask_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_exportmessagestask_groups_id_seq OWNED BY msgs_exportmessagestask_groups.id;


--
-- Name: msgs_exportmessagestask_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_exportmessagestask_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_exportmessagestask_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_exportmessagestask_id_seq OWNED BY msgs_exportmessagestask.id;


--
-- Name: msgs_label; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_label (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    org_id integer NOT NULL,
    uuid character varying(36) NOT NULL,
    created_by_id integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    is_active boolean NOT NULL,
    modified_by_id integer NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    folder_id integer,
    label_type character varying(1) NOT NULL,
    visible_count integer NOT NULL,
    CONSTRAINT msgs_label_visible_count_check CHECK ((visible_count >= 0))
);


--
-- Name: msgs_label_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_label_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_label_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_label_id_seq OWNED BY msgs_label.id;


--
-- Name: msgs_msg; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_msg (
    id integer NOT NULL,
    text text NOT NULL,
    priority integer NOT NULL,
    created_on timestamp with time zone NOT NULL,
    sent_on timestamp with time zone,
    delivered_on timestamp with time zone,
    queued_on timestamp with time zone,
    direction character varying(1) NOT NULL,
    status character varying(1) NOT NULL,
    visibility character varying(1) NOT NULL,
    has_template_error boolean NOT NULL,
    msg_type character varying(1),
    msg_count integer NOT NULL,
    error_count integer NOT NULL,
    next_attempt timestamp with time zone NOT NULL,
    external_id character varying(255),
    broadcast_id integer,
    channel_id integer,
    contact_id integer NOT NULL,
    contact_urn_id integer NOT NULL,
    org_id integer NOT NULL,
    response_to_id integer,
    topup_id integer,
    recording_url character varying(255)
);


--
-- Name: msgs_msg_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_msg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_msg_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_msg_id_seq OWNED BY msgs_msg.id;


--
-- Name: msgs_msg_labels; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE msgs_msg_labels (
    id integer NOT NULL,
    msg_id integer NOT NULL,
    label_id integer NOT NULL
);


--
-- Name: msgs_msg_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE msgs_msg_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msgs_msg_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE msgs_msg_labels_id_seq OWNED BY msgs_msg_labels.id;


--
-- Name: orgs_creditalert; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_creditalert (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    threshold integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: orgs_creditalert_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_creditalert_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_creditalert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_creditalert_id_seq OWNED BY orgs_creditalert.id;


--
-- Name: orgs_invitation; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_invitation (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    email character varying(75) NOT NULL,
    secret character varying(64) NOT NULL,
    host character varying(32) NOT NULL,
    user_group character varying(1) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: orgs_invitation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_invitation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_invitation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_invitation_id_seq OWNED BY orgs_invitation.id;


--
-- Name: orgs_language; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_language (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    iso_code character varying(4) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: orgs_language_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_language_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_language_id_seq OWNED BY orgs_language.id;


--
-- Name: orgs_org; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_org (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(128) NOT NULL,
    plan character varying(16) NOT NULL,
    plan_start timestamp with time zone NOT NULL,
    stripe_customer character varying(32),
    language character varying(64),
    timezone character varying(64) NOT NULL,
    date_format character varying(1) NOT NULL,
    webhook text,
    webhook_events integer NOT NULL,
    msg_last_viewed timestamp with time zone NOT NULL,
    flows_last_viewed timestamp with time zone NOT NULL,
    config text,
    slug character varying(255),
    is_anon boolean NOT NULL,
    country_id integer,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    primary_language_id integer
);


--
-- Name: orgs_org_administrators; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_org_administrators (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: orgs_org_administrators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_administrators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_administrators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_administrators_id_seq OWNED BY orgs_org_administrators.id;


--
-- Name: orgs_org_editors; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_org_editors (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: orgs_org_editors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_editors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_editors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_editors_id_seq OWNED BY orgs_org_editors.id;


--
-- Name: orgs_org_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_id_seq OWNED BY orgs_org.id;


--
-- Name: orgs_org_viewers; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_org_viewers (
    id integer NOT NULL,
    org_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: orgs_org_viewers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_org_viewers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_org_viewers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_org_viewers_id_seq OWNED BY orgs_org_viewers.id;


--
-- Name: orgs_topup; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_topup (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    price integer NOT NULL,
    credits integer NOT NULL,
    expires_on timestamp with time zone NOT NULL,
    stripe_charge character varying(32),
    comment character varying(255),
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    used integer NOT NULL
);


--
-- Name: orgs_topup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_topup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_topup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_topup_id_seq OWNED BY orgs_topup.id;


--
-- Name: orgs_usersettings; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orgs_usersettings (
    id integer NOT NULL,
    language character varying(8) NOT NULL,
    tel character varying(16),
    user_id integer NOT NULL
);


--
-- Name: orgs_usersettings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orgs_usersettings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orgs_usersettings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orgs_usersettings_id_seq OWNED BY orgs_usersettings.id;


--
-- Name: public_lead; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE public_lead (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    email character varying(75) NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: public_lead_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public_lead_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: public_lead_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public_lead_id_seq OWNED BY public_lead.id;


--
-- Name: public_video; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE public_video (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    name character varying(255) NOT NULL,
    summary text NOT NULL,
    description text NOT NULL,
    vimeo_id character varying(255) NOT NULL,
    "order" integer NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: public_video_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public_video_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: public_video_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public_video_id_seq OWNED BY public_video.id;


--
-- Name: reports_report; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE reports_report (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    title character varying(64) NOT NULL,
    description text NOT NULL,
    config text,
    is_published boolean NOT NULL,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL
);


--
-- Name: reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE reports_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reports_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE reports_report_id_seq OWNED BY reports_report.id;


--
-- Name: schedules_schedule; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE schedules_schedule (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    status character varying(1) NOT NULL,
    repeat_hour_of_day integer,
    repeat_day_of_month integer,
    repeat_period character varying(1),
    repeat_days integer,
    last_fire timestamp with time zone,
    next_fire timestamp with time zone,
    created_by_id integer NOT NULL,
    modified_by_id integer NOT NULL
);


--
-- Name: schedules_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE schedules_schedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedules_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE schedules_schedule_id_seq OWNED BY schedules_schedule.id;


--
-- Name: triggers_trigger; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE triggers_trigger (
    id integer NOT NULL,
    is_active boolean NOT NULL,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    keyword character varying(16),
    last_triggered timestamp with time zone,
    trigger_count integer NOT NULL,
    is_archived boolean NOT NULL,
    trigger_type character varying(1) NOT NULL,
    channel_id integer,
    created_by_id integer NOT NULL,
    flow_id integer,
    modified_by_id integer NOT NULL,
    org_id integer NOT NULL,
    schedule_id integer
);


--
-- Name: triggers_trigger_contacts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE triggers_trigger_contacts (
    id integer NOT NULL,
    trigger_id integer NOT NULL,
    contact_id integer NOT NULL
);


--
-- Name: triggers_trigger_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE triggers_trigger_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: triggers_trigger_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE triggers_trigger_contacts_id_seq OWNED BY triggers_trigger_contacts.id;


--
-- Name: triggers_trigger_groups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE triggers_trigger_groups (
    id integer NOT NULL,
    trigger_id integer NOT NULL,
    contactgroup_id integer NOT NULL
);


--
-- Name: triggers_trigger_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE triggers_trigger_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: triggers_trigger_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE triggers_trigger_groups_id_seq OWNED BY triggers_trigger_groups.id;


--
-- Name: triggers_trigger_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE triggers_trigger_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: triggers_trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE triggers_trigger_id_seq OWNED BY triggers_trigger.id;


--
-- Name: users_failedlogin; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users_failedlogin (
    id integer NOT NULL,
    user_id integer NOT NULL,
    failed_on timestamp with time zone NOT NULL
);


--
-- Name: users_failedlogin_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_failedlogin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_failedlogin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_failedlogin_id_seq OWNED BY users_failedlogin.id;


--
-- Name: users_passwordhistory; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users_passwordhistory (
    id integer NOT NULL,
    user_id integer NOT NULL,
    password character varying(255) NOT NULL,
    set_on timestamp with time zone NOT NULL
);


--
-- Name: users_passwordhistory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_passwordhistory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_passwordhistory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_passwordhistory_id_seq OWNED BY users_passwordhistory.id;


--
-- Name: users_recoverytoken; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users_recoverytoken (
    id integer NOT NULL,
    user_id integer NOT NULL,
    token character varying(32) NOT NULL,
    created_on timestamp with time zone NOT NULL
);


--
-- Name: users_recoverytoken_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_recoverytoken_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_recoverytoken_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_recoverytoken_id_seq OWNED BY users_recoverytoken.id;


--
-- Name: values_value; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE values_value (
    id integer NOT NULL,
    rule_uuid character varying(255),
    category character varying(128),
    string_value text NOT NULL,
    decimal_value numeric(36,8),
    datetime_value timestamp with time zone,
    recording_value text,
    created_on timestamp with time zone NOT NULL,
    modified_on timestamp with time zone NOT NULL,
    contact_id integer NOT NULL,
    contact_field_id integer,
    location_value_id integer,
    org_id integer NOT NULL,
    ruleset_id integer,
    run_id integer
);


--
-- Name: values_value_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE values_value_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: values_value_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE values_value_id_seq OWNED BY values_value.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent ALTER COLUMN id SET DEFAULT nextval('api_webhookevent_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult ALTER COLUMN id SET DEFAULT nextval('api_webhookresult_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group ALTER COLUMN id SET DEFAULT nextval('auth_group_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('auth_group_permissions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission ALTER COLUMN id SET DEFAULT nextval('auth_permission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user ALTER COLUMN id SET DEFAULT nextval('auth_user_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups ALTER COLUMN id SET DEFAULT nextval('auth_user_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('auth_user_user_permissions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign ALTER COLUMN id SET DEFAULT nextval('campaigns_campaign_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent ALTER COLUMN id SET DEFAULT nextval('campaigns_campaignevent_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire ALTER COLUMN id SET DEFAULT nextval('campaigns_eventfire_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY celery_taskmeta ALTER COLUMN id SET DEFAULT nextval('celery_taskmeta_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY celery_tasksetmeta ALTER COLUMN id SET DEFAULT nextval('celery_tasksetmeta_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert ALTER COLUMN id SET DEFAULT nextval('channels_alert_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel ALTER COLUMN id SET DEFAULT nextval('channels_channel_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog ALTER COLUMN id SET DEFAULT nextval('channels_channellog_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent ALTER COLUMN id SET DEFAULT nextval('channels_syncevent_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact ALTER COLUMN id SET DEFAULT nextval('contacts_contact_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield ALTER COLUMN id SET DEFAULT nextval('contacts_contactfield_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields ALTER COLUMN id SET DEFAULT nextval('contacts_contactgroup_query_fields_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn ALTER COLUMN id SET DEFAULT nextval('contacts_contacturn_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask ALTER COLUMN id SET DEFAULT nextval('contacts_exportcontactstask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY csv_imports_importtask ALTER COLUMN id SET DEFAULT nextval('csv_imports_importtask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_content_type ALTER COLUMN id SET DEFAULT nextval('django_content_type_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_migrations ALTER COLUMN id SET DEFAULT nextval('django_migrations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY django_site ALTER COLUMN id SET DEFAULT nextval('django_site_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_crontabschedule ALTER COLUMN id SET DEFAULT nextval('djcelery_crontabschedule_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_intervalschedule ALTER COLUMN id SET DEFAULT nextval('djcelery_intervalschedule_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_periodictask ALTER COLUMN id SET DEFAULT nextval('djcelery_periodictask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_taskstate ALTER COLUMN id SET DEFAULT nextval('djcelery_taskstate_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_workerstate ALTER COLUMN id SET DEFAULT nextval('djcelery_workerstate_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionlog ALTER COLUMN id SET DEFAULT nextval('flows_actionlog_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset ALTER COLUMN id SET DEFAULT nextval('flows_actionset_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask ALTER COLUMN id SET DEFAULT nextval('flows_exportflowresultstask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows ALTER COLUMN id SET DEFAULT nextval('flows_exportflowresultstask_flows_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow ALTER COLUMN id SET DEFAULT nextval('flows_flow_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels ALTER COLUMN id SET DEFAULT nextval('flows_flow_labels_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel ALTER COLUMN id SET DEFAULT nextval('flows_flowlabel_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun ALTER COLUMN id SET DEFAULT nextval('flows_flowrun_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups ALTER COLUMN id SET DEFAULT nextval('flows_flowstart_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep ALTER COLUMN id SET DEFAULT nextval('flows_flowstep_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages ALTER COLUMN id SET DEFAULT nextval('flows_flowstep_messages_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion ALTER COLUMN id SET DEFAULT nextval('flows_flowversion_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset ALTER COLUMN id SET DEFAULT nextval('flows_ruleset_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_groupobjectpermission ALTER COLUMN id SET DEFAULT nextval('guardian_groupobjectpermission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY guardian_userobjectpermission ALTER COLUMN id SET DEFAULT nextval('guardian_userobjectpermission_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall ALTER COLUMN id SET DEFAULT nextval('ivr_ivrcall_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary ALTER COLUMN id SET DEFAULT nextval('locations_adminboundary_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias ALTER COLUMN id SET DEFAULT nextval('locations_boundaryalias_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns ALTER COLUMN id SET DEFAULT nextval('msgs_broadcast_urns_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call ALTER COLUMN id SET DEFAULT nextval('msgs_call_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask ALTER COLUMN id SET DEFAULT nextval('msgs_exportmessagestask_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups ALTER COLUMN id SET DEFAULT nextval('msgs_exportmessagestask_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label ALTER COLUMN id SET DEFAULT nextval('msgs_label_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg ALTER COLUMN id SET DEFAULT nextval('msgs_msg_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels ALTER COLUMN id SET DEFAULT nextval('msgs_msg_labels_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert ALTER COLUMN id SET DEFAULT nextval('orgs_creditalert_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation ALTER COLUMN id SET DEFAULT nextval('orgs_invitation_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language ALTER COLUMN id SET DEFAULT nextval('orgs_language_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org ALTER COLUMN id SET DEFAULT nextval('orgs_org_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators ALTER COLUMN id SET DEFAULT nextval('orgs_org_administrators_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors ALTER COLUMN id SET DEFAULT nextval('orgs_org_editors_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers ALTER COLUMN id SET DEFAULT nextval('orgs_org_viewers_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup ALTER COLUMN id SET DEFAULT nextval('orgs_topup_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_usersettings ALTER COLUMN id SET DEFAULT nextval('orgs_usersettings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead ALTER COLUMN id SET DEFAULT nextval('public_lead_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video ALTER COLUMN id SET DEFAULT nextval('public_video_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report ALTER COLUMN id SET DEFAULT nextval('reports_report_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule ALTER COLUMN id SET DEFAULT nextval('schedules_schedule_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups ALTER COLUMN id SET DEFAULT nextval('triggers_trigger_groups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_failedlogin ALTER COLUMN id SET DEFAULT nextval('users_failedlogin_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_passwordhistory ALTER COLUMN id SET DEFAULT nextval('users_passwordhistory_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users_recoverytoken ALTER COLUMN id SET DEFAULT nextval('users_recoverytoken_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value ALTER COLUMN id SET DEFAULT nextval('values_value_id_seq'::regclass);


--
-- Name: api_apitoken_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_pkey PRIMARY KEY (key);


--
-- Name: api_apitoken_user_id_5752cf28bea31ac4_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_user_id_5752cf28bea31ac4_uniq UNIQUE (user_id, org_id);


--
-- Name: api_webhookevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_pkey PRIMARY KEY (id);


--
-- Name: api_webhookresult_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresult_pkey PRIMARY KEY (id);


--
-- Name: auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions_group_id_permission_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_key UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission_content_type_id_codename_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_key UNIQUE (content_type_id, codename);


--
-- Name: auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups_user_id_group_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_key UNIQUE (user_id, group_id);


--
-- Name: auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions_user_id_permission_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_key UNIQUE (user_id, permission_id);


--
-- Name: auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: authtoken_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_pkey PRIMARY KEY (key);


--
-- Name: authtoken_token_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_key UNIQUE (user_id);


--
-- Name: campaigns_campaign_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaign_uuid_70da94f192ee2f54_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_uuid_70da94f192ee2f54_uniq UNIQUE (uuid);


--
-- Name: campaigns_campaignevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_pkey PRIMARY KEY (id);


--
-- Name: campaigns_campaignevent_uuid_652cd08c5c5af6b7_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaignevent_uuid_652cd08c5c5af6b7_uniq UNIQUE (uuid);


--
-- Name: campaigns_eventfire_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT campaigns_eventfire_pkey PRIMARY KEY (id);


--
-- Name: celery_taskmeta_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_taskmeta
    ADD CONSTRAINT celery_taskmeta_pkey PRIMARY KEY (id);


--
-- Name: celery_taskmeta_task_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_taskmeta
    ADD CONSTRAINT celery_taskmeta_task_id_key UNIQUE (task_id);


--
-- Name: celery_tasksetmeta_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_tasksetmeta
    ADD CONSTRAINT celery_tasksetmeta_pkey PRIMARY KEY (id);


--
-- Name: celery_tasksetmeta_taskset_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY celery_tasksetmeta
    ADD CONSTRAINT celery_tasksetmeta_taskset_id_key UNIQUE (taskset_id);


--
-- Name: channels_alert_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_pkey PRIMARY KEY (id);


--
-- Name: channels_channel_claim_code_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_claim_code_key UNIQUE (claim_code);


--
-- Name: channels_channel_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_pkey PRIMARY KEY (id);


--
-- Name: channels_channel_secret_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_secret_key UNIQUE (secret);


--
-- Name: channels_channellog_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT channels_channellog_pkey PRIMARY KEY (id);


--
-- Name: channels_syncevent_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syncevent_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_pkey PRIMARY KEY (id);


--
-- Name: contacts_contact_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contactfield_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_contacts_contactgroup_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_contacts_contactgroup_id_contact_id_key UNIQUE (contactgroup_id, contact_id);


--
-- Name: contacts_contactgroup_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_contactgroup_contacts_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_query_f_contactgroup_id_contactfield__key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_query_f_contactgroup_id_contactfield__key UNIQUE (contactgroup_id, contactfield_id);


--
-- Name: contacts_contactgroup_query_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT contacts_contactgroup_query_fields_pkey PRIMARY KEY (id);


--
-- Name: contacts_contactgroup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_uuid_key UNIQUE (uuid);


--
-- Name: contacts_contacturn_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_pkey PRIMARY KEY (id);


--
-- Name: contacts_contacturn_urn_1dd7ac9b8ad903c2_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_urn_1dd7ac9b8ad903c2_uniq UNIQUE (urn, org_id);


--
-- Name: contacts_exportcontactstask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactstask_pkey PRIMARY KEY (id);


--
-- Name: csv_imports_importtask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY csv_imports_importtask
    ADD CONSTRAINT csv_imports_importtask_pkey PRIMARY KEY (id);


--
-- Name: django_content_type_app_label_45f3b1d93ec8c61c_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_content_type
    ADD CONSTRAINT django_content_type_app_label_45f3b1d93ec8c61c_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: django_site_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY django_site
    ADD CONSTRAINT django_site_pkey PRIMARY KEY (id);


--
-- Name: djcelery_crontabschedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_crontabschedule
    ADD CONSTRAINT djcelery_crontabschedule_pkey PRIMARY KEY (id);


--
-- Name: djcelery_intervalschedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_intervalschedule
    ADD CONSTRAINT djcelery_intervalschedule_pkey PRIMARY KEY (id);


--
-- Name: djcelery_periodictask_name_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT djcelery_periodictask_name_key UNIQUE (name);


--
-- Name: djcelery_periodictask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT djcelery_periodictask_pkey PRIMARY KEY (id);


--
-- Name: djcelery_periodictasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_periodictasks
    ADD CONSTRAINT djcelery_periodictasks_pkey PRIMARY KEY (ident);


--
-- Name: djcelery_taskstate_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_taskstate
    ADD CONSTRAINT djcelery_taskstate_pkey PRIMARY KEY (id);


--
-- Name: djcelery_taskstate_task_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_taskstate
    ADD CONSTRAINT djcelery_taskstate_task_id_key UNIQUE (task_id);


--
-- Name: djcelery_workerstate_hostname_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_workerstate
    ADD CONSTRAINT djcelery_workerstate_hostname_key UNIQUE (hostname);


--
-- Name: djcelery_workerstate_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY djcelery_workerstate
    ADD CONSTRAINT djcelery_workerstate_pkey PRIMARY KEY (id);


--
-- Name: flows_actionlog_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_actionlog
    ADD CONSTRAINT flows_actionlog_pkey PRIMARY KEY (id);


--
-- Name: flows_actionset_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_pkey PRIMARY KEY (id);


--
-- Name: flows_actionset_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_uuid_key UNIQUE (uuid);


--
-- Name: flows_exportflowresultstask_f_exportflowresultstask_id_flow_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultstask_f_exportflowresultstask_id_flow_key UNIQUE (exportflowresultstask_id, flow_id);


--
-- Name: flows_exportflowresultstask_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresultstask_flows_pkey PRIMARY KEY (id);


--
-- Name: flows_exportflowresultstask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultstask_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_entry_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_entry_uuid_key UNIQUE (entry_uuid);


--
-- Name: flows_flow_labels_flow_id_flowlabel_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flow_id_flowlabel_id_key UNIQUE (flow_id, flowlabel_id);


--
-- Name: flows_flow_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_pkey PRIMARY KEY (id);


--
-- Name: flows_flow_uuid_1449b94137c010a4_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_uuid_1449b94137c010a4_uniq UNIQUE (uuid);


--
-- Name: flows_flowlabel_name_25a18a8b44c6e978_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_name_25a18a8b44c6e978_uniq UNIQUE (name, parent_id, org_id);


--
-- Name: flows_flowlabel_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_pkey PRIMARY KEY (id);


--
-- Name: flows_flowrun_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_contacts_flowstart_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_flowstart_id_contact_id_key UNIQUE (flowstart_id, contact_id);


--
-- Name: flows_flowstart_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowstart_contacts_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_groups_flowstart_id_contactgroup_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_flowstart_id_contactgroup_id_key UNIQUE (flowstart_id, contactgroup_id);


--
-- Name: flows_flowstart_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flowstart_groups_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstart_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstep_messages_flowstep_id_msg_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_flowstep_id_msg_id_key UNIQUE (flowstep_id, msg_id);


--
-- Name: flows_flowstep_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_pkey PRIMARY KEY (id);


--
-- Name: flows_flowstep_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT flows_flowstep_pkey PRIMARY KEY (id);


--
-- Name: flows_flowversion_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT flows_flowversion_pkey PRIMARY KEY (id);


--
-- Name: flows_ruleset_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_pkey PRIMARY KEY (id);


--
-- Name: flows_ruleset_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_uuid_key UNIQUE (uuid);


--
-- Name: guardian_groupobjectpermissio_group_id_permission_id_object_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobjectpermissio_group_id_permission_id_object_key UNIQUE (group_id, permission_id, object_pk);


--
-- Name: guardian_groupobjectpermission_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_groupobjectpermission
    ADD CONSTRAINT guardian_groupobjectpermission_pkey PRIMARY KEY (id);


--
-- Name: guardian_userobjectpermission_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjectpermission_pkey PRIMARY KEY (id);


--
-- Name: guardian_userobjectpermission_user_id_permission_id_object__key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY guardian_userobjectpermission
    ADD CONSTRAINT guardian_userobjectpermission_user_id_permission_id_object__key UNIQUE (user_id, permission_id, object_pk);


--
-- Name: ivr_ivrcall_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_pkey PRIMARY KEY (id);


--
-- Name: locations_adminboundary_osm_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_osm_id_key UNIQUE (osm_id);


--
-- Name: locations_adminboundary_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locations_adminboundary_pkey PRIMARY KEY (id);


--
-- Name: locations_boundaryalias_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_contacts_broadcast_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_broadcast_id_contact_id_key UNIQUE (broadcast_id, contact_id);


--
-- Name: msgs_broadcast_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadcast_contacts_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_groups_broadcast_id_contactgroup_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_broadcast_id_contactgroup_id_key UNIQUE (broadcast_id, contactgroup_id);


--
-- Name: msgs_broadcast_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadcast_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_pkey PRIMARY KEY (id);


--
-- Name: msgs_broadcast_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_schedule_id_key UNIQUE (schedule_id);


--
-- Name: msgs_broadcast_urns_broadcast_id_contacturn_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_broadcast_id_contacturn_id_key UNIQUE (broadcast_id, contacturn_id);


--
-- Name: msgs_broadcast_urns_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadcast_urns_pkey PRIMARY KEY (id);


--
-- Name: msgs_call_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT msgs_call_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask_group_exportmessagestask_id_contact_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagestask_group_exportmessagestask_id_contact_key UNIQUE (exportmessagestask_id, contactgroup_id);


--
-- Name: msgs_exportmessagestask_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT msgs_exportmessagestask_groups_pkey PRIMARY KEY (id);


--
-- Name: msgs_exportmessagestask_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_pkey PRIMARY KEY (id);


--
-- Name: msgs_label_org_id_7ab7f9bb751e78b4_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_org_id_7ab7f9bb751e78b4_uniq UNIQUE (org_id, name);


--
-- Name: msgs_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_pkey PRIMARY KEY (id);


--
-- Name: msgs_label_uuid_7d50eba9220d6f69_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_uuid_7d50eba9220d6f69_uniq UNIQUE (uuid);


--
-- Name: msgs_msg_labels_msg_id_label_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_msg_id_label_id_key UNIQUE (msg_id, label_id);


--
-- Name: msgs_msg_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_pkey PRIMARY KEY (id);


--
-- Name: msgs_msg_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_pkey PRIMARY KEY (id);


--
-- Name: orgs_creditalert_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_pkey PRIMARY KEY (id);


--
-- Name: orgs_invitation_secret_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_secret_key UNIQUE (secret);


--
-- Name: orgs_language_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_administrators_org_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_org_id_user_id_key UNIQUE (org_id, user_id);


--
-- Name: orgs_org_administrators_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_editors_org_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_org_id_user_id_key UNIQUE (org_id, user_id);


--
-- Name: orgs_org_editors_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_pkey PRIMARY KEY (id);


--
-- Name: orgs_org_slug_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_slug_key UNIQUE (slug);


--
-- Name: orgs_org_viewers_org_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_org_id_user_id_key UNIQUE (org_id, user_id);


--
-- Name: orgs_org_viewers_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_pkey PRIMARY KEY (id);


--
-- Name: orgs_topup_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_pkey PRIMARY KEY (id);


--
-- Name: orgs_usersettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_pkey PRIMARY KEY (id);


--
-- Name: public_lead_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT public_lead_pkey PRIMARY KEY (id);


--
-- Name: public_video_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT public_video_pkey PRIMARY KEY (id);


--
-- Name: reports_report_org_id_6c82d69e44350d9d_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_org_id_6c82d69e44350d9d_uniq UNIQUE (org_id, title);


--
-- Name: reports_report_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_pkey PRIMARY KEY (id);


--
-- Name: schedules_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT schedules_schedule_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_channel_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_channel_id_key UNIQUE (channel_id);


--
-- Name: triggers_trigger_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_contacts_trigger_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trigger_contacts_trigger_id_contact_id_key UNIQUE (trigger_id, contact_id);


--
-- Name: triggers_trigger_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_groups_trigger_id_contactgroup_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_trigger_groups_trigger_id_contactgroup_id_key UNIQUE (trigger_id, contactgroup_id);


--
-- Name: triggers_trigger_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_pkey PRIMARY KEY (id);


--
-- Name: triggers_trigger_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_schedule_id_key UNIQUE (schedule_id);


--
-- Name: users_failedlogin_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_failedlogin
    ADD CONSTRAINT users_failedlogin_pkey PRIMARY KEY (id);


--
-- Name: users_passwordhistory_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_passwordhistory
    ADD CONSTRAINT users_passwordhistory_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_pkey PRIMARY KEY (id);


--
-- Name: users_recoverytoken_token_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users_recoverytoken
    ADD CONSTRAINT users_recoverytoken_token_key UNIQUE (token);


--
-- Name: values_value_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_pkey PRIMARY KEY (id);


--
-- Name: api_apitoken_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_apitoken_9cf869aa ON api_apitoken USING btree (org_id);


--
-- Name: api_apitoken_e8701ad4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_apitoken_e8701ad4 ON api_apitoken USING btree (user_id);


--
-- Name: api_apitoken_key_6326fe0e62af2891_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_apitoken_key_6326fe0e62af2891_like ON api_apitoken USING btree (key varchar_pattern_ops);


--
-- Name: api_webhookevent_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_72eb6c85 ON api_webhookevent USING btree (channel_id);


--
-- Name: api_webhookevent_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_9cf869aa ON api_webhookevent USING btree (org_id);


--
-- Name: api_webhookevent_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_b3da0983 ON api_webhookevent USING btree (modified_by_id);


--
-- Name: api_webhookevent_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookevent_e93cb7eb ON api_webhookevent USING btree (created_by_id);


--
-- Name: api_webhookresult_4437cfac; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookresult_4437cfac ON api_webhookresult USING btree (event_id);


--
-- Name: api_webhookresult_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookresult_b3da0983 ON api_webhookresult USING btree (modified_by_id);


--
-- Name: api_webhookresult_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX api_webhookresult_e93cb7eb ON api_webhookresult USING btree (created_by_id);


--
-- Name: auth_group_name_253ae2a6331666e8_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_group_name_253ae2a6331666e8_like ON auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_0e939a4f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_group_permissions_0e939a4f ON auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_8373b171; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_group_permissions_8373b171 ON auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_417f1b1c; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_permission_417f1b1c ON auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_0e939a4f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_user_groups_0e939a4f ON auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_e8701ad4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_user_groups_e8701ad4 ON auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_8373b171; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_user_user_permissions_8373b171 ON auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_e8701ad4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_user_user_permissions_e8701ad4 ON auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_51b3b110094b8aae_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX auth_user_username_51b3b110094b8aae_like ON auth_user USING btree (username varchar_pattern_ops);


--
-- Name: authtoken_token_key_7222ec672cd32dcd_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX authtoken_token_key_7222ec672cd32dcd_like ON authtoken_token USING btree (key varchar_pattern_ops);


--
-- Name: campaigns_campaign_0e939a4f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_0e939a4f ON campaigns_campaign USING btree (group_id);


--
-- Name: campaigns_campaign_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_9cf869aa ON campaigns_campaign USING btree (org_id);


--
-- Name: campaigns_campaign_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_b3da0983 ON campaigns_campaign USING btree (modified_by_id);


--
-- Name: campaigns_campaign_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaign_e93cb7eb ON campaigns_campaign USING btree (created_by_id);


--
-- Name: campaigns_campaignevent_61d66954; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_61d66954 ON campaigns_campaignevent USING btree (relative_to_id);


--
-- Name: campaigns_campaignevent_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_7f26ac5b ON campaigns_campaignevent USING btree (flow_id);


--
-- Name: campaigns_campaignevent_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_b3da0983 ON campaigns_campaignevent USING btree (modified_by_id);


--
-- Name: campaigns_campaignevent_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_e93cb7eb ON campaigns_campaignevent USING btree (created_by_id);


--
-- Name: campaigns_campaignevent_f14acec3; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_campaignevent_f14acec3 ON campaigns_campaignevent USING btree (campaign_id);


--
-- Name: campaigns_eventfire_4437cfac; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_eventfire_4437cfac ON campaigns_eventfire USING btree (event_id);


--
-- Name: campaigns_eventfire_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX campaigns_eventfire_6d82f13d ON campaigns_eventfire USING btree (contact_id);


--
-- Name: celery_taskmeta_hidden; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_taskmeta_hidden ON celery_taskmeta USING btree (hidden);


--
-- Name: celery_taskmeta_task_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_taskmeta_task_id_like ON celery_taskmeta USING btree (task_id varchar_pattern_ops);


--
-- Name: celery_tasksetmeta_hidden; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_tasksetmeta_hidden ON celery_tasksetmeta USING btree (hidden);


--
-- Name: celery_tasksetmeta_taskset_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX celery_tasksetmeta_taskset_id_like ON celery_tasksetmeta USING btree (taskset_id varchar_pattern_ops);


--
-- Name: channels_alert_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_72eb6c85 ON channels_alert USING btree (channel_id);


--
-- Name: channels_alert_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_b3da0983 ON channels_alert USING btree (modified_by_id);


--
-- Name: channels_alert_c8730bec; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_c8730bec ON channels_alert USING btree (sync_event_id);


--
-- Name: channels_alert_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_alert_e93cb7eb ON channels_alert USING btree (created_by_id);


--
-- Name: channels_channel_6be37982; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_6be37982 ON channels_channel USING btree (parent_id);


--
-- Name: channels_channel_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_9cf869aa ON channels_channel USING btree (org_id);


--
-- Name: channels_channel_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_b3da0983 ON channels_channel USING btree (modified_by_id);


--
-- Name: channels_channel_claim_code_1d76c97784145fd7_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_claim_code_1d76c97784145fd7_like ON channels_channel USING btree (claim_code varchar_pattern_ops);


--
-- Name: channels_channel_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_e93cb7eb ON channels_channel USING btree (created_by_id);


--
-- Name: channels_channel_ef7c876f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_ef7c876f ON channels_channel USING btree (uuid);


--
-- Name: channels_channel_secret_301da0bd8988cfef_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_secret_301da0bd8988cfef_like ON channels_channel USING btree (secret varchar_pattern_ops);


--
-- Name: channels_channel_uuid_3f1c42234e8f4a30_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channel_uuid_3f1c42234e8f4a30_like ON channels_channel USING btree (uuid varchar_pattern_ops);


--
-- Name: channels_channellog_0cc31d7b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_channellog_0cc31d7b ON channels_channellog USING btree (msg_id);


--
-- Name: channels_syncevent_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_syncevent_72eb6c85 ON channels_syncevent USING btree (channel_id);


--
-- Name: channels_syncevent_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_syncevent_b3da0983 ON channels_syncevent USING btree (modified_by_id);


--
-- Name: channels_syncevent_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX channels_syncevent_e93cb7eb ON channels_syncevent USING btree (created_by_id);


--
-- Name: contacts_contact_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contact_9cf869aa ON contacts_contact USING btree (org_id);


--
-- Name: contacts_contact_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contact_b3da0983 ON contacts_contact USING btree (modified_by_id);


--
-- Name: contacts_contact_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contact_e93cb7eb ON contacts_contact USING btree (created_by_id);


--
-- Name: contacts_contact_uuid_1615f91d2f7b8c6_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contact_uuid_1615f91d2f7b8c6_like ON contacts_contact USING btree (uuid varchar_pattern_ops);


--
-- Name: contacts_contactfield_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactfield_9cf869aa ON contacts_contactfield USING btree (org_id);


--
-- Name: contacts_contactgroup_905540a6; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_905540a6 ON contacts_contactgroup USING btree (import_task_id);


--
-- Name: contacts_contactgroup_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_9cf869aa ON contacts_contactgroup USING btree (org_id);


--
-- Name: contacts_contactgroup_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_b3da0983 ON contacts_contactgroup USING btree (modified_by_id);


--
-- Name: contacts_contactgroup_contacts_0b1b2ae4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_contacts_0b1b2ae4 ON contacts_contactgroup_contacts USING btree (contactgroup_id);


--
-- Name: contacts_contactgroup_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_contacts_6d82f13d ON contacts_contactgroup_contacts USING btree (contact_id);


--
-- Name: contacts_contactgroup_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_e93cb7eb ON contacts_contactgroup USING btree (created_by_id);


--
-- Name: contacts_contactgroup_query_fields_0b1b2ae4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_query_fields_0b1b2ae4 ON contacts_contactgroup_query_fields USING btree (contactgroup_id);


--
-- Name: contacts_contactgroup_query_fields_0d0cd403; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contactgroup_query_fields_0d0cd403 ON contacts_contactgroup_query_fields USING btree (contactfield_id);


--
-- Name: contacts_contacturn_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contacturn_6d82f13d ON contacts_contacturn USING btree (contact_id);


--
-- Name: contacts_contacturn_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contacturn_72eb6c85 ON contacts_contacturn USING btree (channel_id);


--
-- Name: contacts_contacturn_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_contacturn_9cf869aa ON contacts_contacturn USING btree (org_id);


--
-- Name: contacts_exportcontactstask_0e939a4f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_0e939a4f ON contacts_exportcontactstask USING btree (group_id);


--
-- Name: contacts_exportcontactstask_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_9cf869aa ON contacts_exportcontactstask USING btree (org_id);


--
-- Name: contacts_exportcontactstask_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_b3da0983 ON contacts_exportcontactstask USING btree (modified_by_id);


--
-- Name: contacts_exportcontactstask_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX contacts_exportcontactstask_e93cb7eb ON contacts_exportcontactstask USING btree (created_by_id);


--
-- Name: csv_imports_importtask_created_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX csv_imports_importtask_created_by_id ON csv_imports_importtask USING btree (created_by_id);


--
-- Name: csv_imports_importtask_modified_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX csv_imports_importtask_modified_by_id ON csv_imports_importtask USING btree (modified_by_id);


--
-- Name: django_session_de54fa62; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX django_session_de54fa62 ON django_session USING btree (expire_date);


--
-- Name: django_session_session_key_461cfeaa630ca218_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX django_session_session_key_461cfeaa630ca218_like ON django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: djcelery_periodictask_crontab_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_periodictask_crontab_id ON djcelery_periodictask USING btree (crontab_id);


--
-- Name: djcelery_periodictask_interval_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_periodictask_interval_id ON djcelery_periodictask USING btree (interval_id);


--
-- Name: djcelery_periodictask_name_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_periodictask_name_like ON djcelery_periodictask USING btree (name varchar_pattern_ops);


--
-- Name: djcelery_taskstate_hidden; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_hidden ON djcelery_taskstate USING btree (hidden);


--
-- Name: djcelery_taskstate_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_name ON djcelery_taskstate USING btree (name);


--
-- Name: djcelery_taskstate_name_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_name_like ON djcelery_taskstate USING btree (name varchar_pattern_ops);


--
-- Name: djcelery_taskstate_state; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_state ON djcelery_taskstate USING btree (state);


--
-- Name: djcelery_taskstate_state_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_state_like ON djcelery_taskstate USING btree (state varchar_pattern_ops);


--
-- Name: djcelery_taskstate_task_id_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_task_id_like ON djcelery_taskstate USING btree (task_id varchar_pattern_ops);


--
-- Name: djcelery_taskstate_tstamp; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_tstamp ON djcelery_taskstate USING btree (tstamp);


--
-- Name: djcelery_taskstate_worker_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_taskstate_worker_id ON djcelery_taskstate USING btree (worker_id);


--
-- Name: djcelery_workerstate_hostname_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_workerstate_hostname_like ON djcelery_workerstate USING btree (hostname varchar_pattern_ops);


--
-- Name: djcelery_workerstate_last_heartbeat; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX djcelery_workerstate_last_heartbeat ON djcelery_workerstate USING btree (last_heartbeat);


--
-- Name: flows_actionlog_0acf093b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_actionlog_0acf093b ON flows_actionlog USING btree (run_id);


--
-- Name: flows_actionset_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_actionset_7f26ac5b ON flows_actionset USING btree (flow_id);


--
-- Name: flows_actionset_uuid_402f1978d948f21d_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_actionset_uuid_402f1978d948f21d_like ON flows_actionset USING btree (uuid varchar_pattern_ops);


--
-- Name: flows_exportflowresultstask_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_9cf869aa ON flows_exportflowresultstask USING btree (org_id);


--
-- Name: flows_exportflowresultstask_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_b3da0983 ON flows_exportflowresultstask USING btree (modified_by_id);


--
-- Name: flows_exportflowresultstask_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_e93cb7eb ON flows_exportflowresultstask USING btree (created_by_id);


--
-- Name: flows_exportflowresultstask_flows_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_flows_7f26ac5b ON flows_exportflowresultstask_flows USING btree (flow_id);


--
-- Name: flows_exportflowresultstask_flows_b21ac655; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_exportflowresultstask_flows_b21ac655 ON flows_exportflowresultstask_flows USING btree (exportflowresultstask_id);


--
-- Name: flows_flow_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_9cf869aa ON flows_flow USING btree (org_id);


--
-- Name: flows_flow_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_b3da0983 ON flows_flow USING btree (modified_by_id);


--
-- Name: flows_flow_bc7c970b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_bc7c970b ON flows_flow USING btree (saved_by_id);


--
-- Name: flows_flow_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_e93cb7eb ON flows_flow USING btree (created_by_id);


--
-- Name: flows_flow_entry_uuid_6db134a69882563d_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_entry_uuid_6db134a69882563d_like ON flows_flow USING btree (entry_uuid varchar_pattern_ops);


--
-- Name: flows_flow_labels_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_labels_7f26ac5b ON flows_flow_labels USING btree (flow_id);


--
-- Name: flows_flow_labels_da1e9929; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flow_labels_da1e9929 ON flows_flow_labels USING btree (flowlabel_id);


--
-- Name: flows_flowlabel_6be37982; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowlabel_6be37982 ON flows_flowlabel USING btree (parent_id);


--
-- Name: flows_flowlabel_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowlabel_9cf869aa ON flows_flowlabel USING btree (org_id);


--
-- Name: flows_flowrun_324ac644; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_324ac644 ON flows_flowrun USING btree (start_id);


--
-- Name: flows_flowrun_5d26c52f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_5d26c52f ON flows_flowrun USING btree (call_id);


--
-- Name: flows_flowrun_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_6d82f13d ON flows_flowrun USING btree (contact_id);


--
-- Name: flows_flowrun_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowrun_7f26ac5b ON flows_flowrun USING btree (flow_id);


--
-- Name: flows_flowstart_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_7f26ac5b ON flows_flowstart USING btree (flow_id);


--
-- Name: flows_flowstart_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_b3da0983 ON flows_flowstart USING btree (modified_by_id);


--
-- Name: flows_flowstart_contacts_3f45c555; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_contacts_3f45c555 ON flows_flowstart_contacts USING btree (flowstart_id);


--
-- Name: flows_flowstart_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_contacts_6d82f13d ON flows_flowstart_contacts USING btree (contact_id);


--
-- Name: flows_flowstart_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_e93cb7eb ON flows_flowstart USING btree (created_by_id);


--
-- Name: flows_flowstart_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_groups_0b1b2ae4 ON flows_flowstart_groups USING btree (contactgroup_id);


--
-- Name: flows_flowstart_groups_3f45c555; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstart_groups_3f45c555 ON flows_flowstart_groups USING btree (flowstart_id);


--
-- Name: flows_flowstep_017416d4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_017416d4 ON flows_flowstep USING btree (step_uuid);


--
-- Name: flows_flowstep_0acf093b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_0acf093b ON flows_flowstep USING btree (run_id);


--
-- Name: flows_flowstep_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_6d82f13d ON flows_flowstep USING btree (contact_id);


--
-- Name: flows_flowstep_a8b6e9f0; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_a8b6e9f0 ON flows_flowstep USING btree (left_on);


--
-- Name: flows_flowstep_messages_0cc31d7b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_messages_0cc31d7b ON flows_flowstep_messages USING btree (msg_id);


--
-- Name: flows_flowstep_messages_c01a422b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_messages_c01a422b ON flows_flowstep_messages USING btree (flowstep_id);


--
-- Name: flows_flowstep_step_next_left_null_rule; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_step_next_left_null_rule ON flows_flowstep USING btree (step_uuid, next_uuid, left_on) WHERE (rule_uuid IS NULL);


--
-- Name: flows_flowstep_step_uuid_1e0747218e80dac8_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_step_uuid_1e0747218e80dac8_idx ON flows_flowstep USING btree (step_uuid, next_uuid, rule_uuid, left_on);


--
-- Name: flows_flowstep_step_uuid_404f8c812c9e4ed2_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowstep_step_uuid_404f8c812c9e4ed2_like ON flows_flowstep USING btree (step_uuid varchar_pattern_ops);


--
-- Name: flows_flowversion_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowversion_7f26ac5b ON flows_flowversion USING btree (flow_id);


--
-- Name: flows_flowversion_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowversion_b3da0983 ON flows_flowversion USING btree (modified_by_id);


--
-- Name: flows_flowversion_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_flowversion_e93cb7eb ON flows_flowversion USING btree (created_by_id);


--
-- Name: flows_ruleset_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_ruleset_7f26ac5b ON flows_ruleset USING btree (flow_id);


--
-- Name: flows_ruleset_uuid_369aa88ed4bb10e1_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX flows_ruleset_uuid_369aa88ed4bb10e1_like ON flows_ruleset USING btree (uuid varchar_pattern_ops);


--
-- Name: guardian_groupobjectpermission_content_type_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_groupobjectpermission_content_type_id ON guardian_groupobjectpermission USING btree (content_type_id);


--
-- Name: guardian_groupobjectpermission_group_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_groupobjectpermission_group_id ON guardian_groupobjectpermission USING btree (group_id);


--
-- Name: guardian_groupobjectpermission_permission_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_groupobjectpermission_permission_id ON guardian_groupobjectpermission USING btree (permission_id);


--
-- Name: guardian_userobjectpermission_content_type_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_userobjectpermission_content_type_id ON guardian_userobjectpermission USING btree (content_type_id);


--
-- Name: guardian_userobjectpermission_permission_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_userobjectpermission_permission_id ON guardian_userobjectpermission USING btree (permission_id);


--
-- Name: guardian_userobjectpermission_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX guardian_userobjectpermission_user_id ON guardian_userobjectpermission USING btree (user_id);


--
-- Name: ivr_ivrcall_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_6d82f13d ON ivr_ivrcall USING btree (contact_id);


--
-- Name: ivr_ivrcall_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_72eb6c85 ON ivr_ivrcall USING btree (channel_id);


--
-- Name: ivr_ivrcall_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_7f26ac5b ON ivr_ivrcall USING btree (flow_id);


--
-- Name: ivr_ivrcall_842dde28; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_842dde28 ON ivr_ivrcall USING btree (contact_urn_id);


--
-- Name: ivr_ivrcall_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_9cf869aa ON ivr_ivrcall USING btree (org_id);


--
-- Name: ivr_ivrcall_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_b3da0983 ON ivr_ivrcall USING btree (modified_by_id);


--
-- Name: ivr_ivrcall_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX ivr_ivrcall_e93cb7eb ON ivr_ivrcall USING btree (created_by_id);


--
-- Name: locations_adminboundary_6be37982; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_6be37982 ON locations_adminboundary USING btree (parent_id);


--
-- Name: locations_adminboundary_geometry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_geometry_id ON locations_adminboundary USING gist (geometry);


--
-- Name: locations_adminboundary_osm_id_135faf5e33f83ebd_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_osm_id_135faf5e33f83ebd_like ON locations_adminboundary USING btree (osm_id varchar_pattern_ops);


--
-- Name: locations_adminboundary_simplified_geometry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_adminboundary_simplified_geometry_id ON locations_adminboundary USING gist (simplified_geometry);


--
-- Name: locations_boundaryalias_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_9cf869aa ON locations_boundaryalias USING btree (org_id);


--
-- Name: locations_boundaryalias_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_b3da0983 ON locations_boundaryalias USING btree (modified_by_id);


--
-- Name: locations_boundaryalias_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_e93cb7eb ON locations_boundaryalias USING btree (created_by_id);


--
-- Name: locations_boundaryalias_eb01ad15; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX locations_boundaryalias_eb01ad15 ON locations_boundaryalias USING btree (boundary_id);


--
-- Name: msg_visibility_direction_type_created_inbound; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msg_visibility_direction_type_created_inbound ON msgs_msg USING btree (org_id, visibility, direction, msg_type, created_on DESC) WHERE ((direction)::text = 'I'::text);


--
-- Name: msgs_broadcast_6be37982; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_6be37982 ON msgs_broadcast USING btree (parent_id);


--
-- Name: msgs_broadcast_6d10fce5; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_6d10fce5 ON msgs_broadcast USING btree (created_on);


--
-- Name: msgs_broadcast_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_72eb6c85 ON msgs_broadcast USING btree (channel_id);


--
-- Name: msgs_broadcast_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_9cf869aa ON msgs_broadcast USING btree (org_id);


--
-- Name: msgs_broadcast_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_b3da0983 ON msgs_broadcast USING btree (modified_by_id);


--
-- Name: msgs_broadcast_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_contacts_6d82f13d ON msgs_broadcast_contacts USING btree (contact_id);


--
-- Name: msgs_broadcast_contacts_b0cb7d59; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_contacts_b0cb7d59 ON msgs_broadcast_contacts USING btree (broadcast_id);


--
-- Name: msgs_broadcast_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_e93cb7eb ON msgs_broadcast USING btree (created_by_id);


--
-- Name: msgs_broadcast_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_groups_0b1b2ae4 ON msgs_broadcast_groups USING btree (contactgroup_id);


--
-- Name: msgs_broadcast_groups_b0cb7d59; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_groups_b0cb7d59 ON msgs_broadcast_groups USING btree (broadcast_id);


--
-- Name: msgs_broadcast_urns_5a8e6a7d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_urns_5a8e6a7d ON msgs_broadcast_urns USING btree (contacturn_id);


--
-- Name: msgs_broadcast_urns_b0cb7d59; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_broadcast_urns_b0cb7d59 ON msgs_broadcast_urns USING btree (broadcast_id);


--
-- Name: msgs_call_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_6d82f13d ON msgs_call USING btree (contact_id);


--
-- Name: msgs_call_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_72eb6c85 ON msgs_call USING btree (channel_id);


--
-- Name: msgs_call_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_9cf869aa ON msgs_call USING btree (org_id);


--
-- Name: msgs_call_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_b3da0983 ON msgs_call USING btree (modified_by_id);


--
-- Name: msgs_call_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_call_e93cb7eb ON msgs_call USING btree (created_by_id);


--
-- Name: msgs_exportmessagestask_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportmessagestask_9cf869aa ON msgs_exportmessagestask USING btree (org_id);


--
-- Name: msgs_exportmessagestask_abec2aca; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportmessagestask_abec2aca ON msgs_exportmessagestask USING btree (label_id);


--
-- Name: msgs_exportmessagestask_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportmessagestask_b3da0983 ON msgs_exportmessagestask USING btree (modified_by_id);


--
-- Name: msgs_exportmessagestask_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportmessagestask_e93cb7eb ON msgs_exportmessagestask USING btree (created_by_id);


--
-- Name: msgs_exportmessagestask_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportmessagestask_groups_0b1b2ae4 ON msgs_exportmessagestask_groups USING btree (contactgroup_id);


--
-- Name: msgs_exportmessagestask_groups_9ad8bdea; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_exportmessagestask_groups_9ad8bdea ON msgs_exportmessagestask_groups USING btree (exportmessagestask_id);


--
-- Name: msgs_label_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_9cf869aa ON msgs_label USING btree (org_id);


--
-- Name: msgs_label_a8a44dbb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_a8a44dbb ON msgs_label USING btree (folder_id);


--
-- Name: msgs_label_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_b3da0983 ON msgs_label USING btree (modified_by_id);


--
-- Name: msgs_label_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_label_e93cb7eb ON msgs_label USING btree (created_by_id);


--
-- Name: msgs_msg_0e684294; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_0e684294 ON msgs_msg USING btree (external_id);


--
-- Name: msgs_msg_6bd7b554; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_6bd7b554 ON msgs_msg USING btree (response_to_id);


--
-- Name: msgs_msg_6d10fce5; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_6d10fce5 ON msgs_msg USING btree (created_on);


--
-- Name: msgs_msg_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_6d82f13d ON msgs_msg USING btree (contact_id);


--
-- Name: msgs_msg_72eb6c85; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_72eb6c85 ON msgs_msg USING btree (channel_id);


--
-- Name: msgs_msg_842dde28; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_842dde28 ON msgs_msg USING btree (contact_urn_id);


--
-- Name: msgs_msg_9acb4454; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_9acb4454 ON msgs_msg USING btree (status);


--
-- Name: msgs_msg_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_9cf869aa ON msgs_msg USING btree (org_id);


--
-- Name: msgs_msg_a5d9fd84; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_a5d9fd84 ON msgs_msg USING btree (topup_id);


--
-- Name: msgs_msg_b0cb7d59; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_b0cb7d59 ON msgs_msg USING btree (broadcast_id);


--
-- Name: msgs_msg_external_id_75d6fcace8b54b05_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_external_id_75d6fcace8b54b05_like ON msgs_msg USING btree (external_id varchar_pattern_ops);


--
-- Name: msgs_msg_f79b1d64; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_f79b1d64 ON msgs_msg USING btree (visibility);


--
-- Name: msgs_msg_labels_0cc31d7b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_labels_0cc31d7b ON msgs_msg_labels USING btree (msg_id);


--
-- Name: msgs_msg_labels_abec2aca; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_labels_abec2aca ON msgs_msg_labels USING btree (label_id);


--
-- Name: msgs_msg_org_failed_created_on; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_org_failed_created_on ON msgs_msg USING btree (org_id, direction, visibility, created_on DESC) WHERE ((status)::text = 'F'::text);


--
-- Name: msgs_msg_status_5a4b234c664548c7_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_status_5a4b234c664548c7_like ON msgs_msg USING btree (status varchar_pattern_ops);


--
-- Name: msgs_msg_visibility_27c941c1446e92db_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX msgs_msg_visibility_27c941c1446e92db_like ON msgs_msg USING btree (visibility varchar_pattern_ops);


--
-- Name: orgs_creditalert_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_creditalert_9cf869aa ON orgs_creditalert USING btree (org_id);


--
-- Name: orgs_creditalert_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_creditalert_b3da0983 ON orgs_creditalert USING btree (modified_by_id);


--
-- Name: orgs_creditalert_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_creditalert_e93cb7eb ON orgs_creditalert USING btree (created_by_id);


--
-- Name: orgs_invitation_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_9cf869aa ON orgs_invitation USING btree (org_id);


--
-- Name: orgs_invitation_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_b3da0983 ON orgs_invitation USING btree (modified_by_id);


--
-- Name: orgs_invitation_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_e93cb7eb ON orgs_invitation USING btree (created_by_id);


--
-- Name: orgs_invitation_secret_579b9a3ce8d65a51_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_invitation_secret_579b9a3ce8d65a51_like ON orgs_invitation USING btree (secret varchar_pattern_ops);


--
-- Name: orgs_language_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_language_9cf869aa ON orgs_language USING btree (org_id);


--
-- Name: orgs_language_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_language_b3da0983 ON orgs_language USING btree (modified_by_id);


--
-- Name: orgs_language_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_language_e93cb7eb ON orgs_language USING btree (created_by_id);


--
-- Name: orgs_org_199f5f21; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_199f5f21 ON orgs_org USING btree (primary_language_id);


--
-- Name: orgs_org_93bfec8a; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_93bfec8a ON orgs_org USING btree (country_id);


--
-- Name: orgs_org_administrators_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_administrators_9cf869aa ON orgs_org_administrators USING btree (org_id);


--
-- Name: orgs_org_administrators_e8701ad4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_administrators_e8701ad4 ON orgs_org_administrators USING btree (user_id);


--
-- Name: orgs_org_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_b3da0983 ON orgs_org USING btree (modified_by_id);


--
-- Name: orgs_org_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_e93cb7eb ON orgs_org USING btree (created_by_id);


--
-- Name: orgs_org_editors_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_editors_9cf869aa ON orgs_org_editors USING btree (org_id);


--
-- Name: orgs_org_editors_e8701ad4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_editors_e8701ad4 ON orgs_org_editors USING btree (user_id);


--
-- Name: orgs_org_slug_66e15e03ab4265ba_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_slug_66e15e03ab4265ba_like ON orgs_org USING btree (slug varchar_pattern_ops);


--
-- Name: orgs_org_viewers_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_viewers_9cf869aa ON orgs_org_viewers USING btree (org_id);


--
-- Name: orgs_org_viewers_e8701ad4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_org_viewers_e8701ad4 ON orgs_org_viewers USING btree (user_id);


--
-- Name: orgs_topup_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_topup_9cf869aa ON orgs_topup USING btree (org_id);


--
-- Name: orgs_topup_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_topup_b3da0983 ON orgs_topup USING btree (modified_by_id);


--
-- Name: orgs_topup_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_topup_e93cb7eb ON orgs_topup USING btree (created_by_id);


--
-- Name: orgs_usersettings_e8701ad4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX orgs_usersettings_e8701ad4 ON orgs_usersettings USING btree (user_id);


--
-- Name: public_lead_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_lead_b3da0983 ON public_lead USING btree (modified_by_id);


--
-- Name: public_lead_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_lead_e93cb7eb ON public_lead USING btree (created_by_id);


--
-- Name: public_video_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_video_b3da0983 ON public_video USING btree (modified_by_id);


--
-- Name: public_video_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX public_video_e93cb7eb ON public_video USING btree (created_by_id);


--
-- Name: reports_report_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX reports_report_9cf869aa ON reports_report USING btree (org_id);


--
-- Name: reports_report_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX reports_report_b3da0983 ON reports_report USING btree (modified_by_id);


--
-- Name: reports_report_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX reports_report_e93cb7eb ON reports_report USING btree (created_by_id);


--
-- Name: schedules_schedule_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX schedules_schedule_b3da0983 ON schedules_schedule USING btree (modified_by_id);


--
-- Name: schedules_schedule_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX schedules_schedule_e93cb7eb ON schedules_schedule USING btree (created_by_id);


--
-- Name: triggers_trigger_7f26ac5b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_7f26ac5b ON triggers_trigger USING btree (flow_id);


--
-- Name: triggers_trigger_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_9cf869aa ON triggers_trigger USING btree (org_id);


--
-- Name: triggers_trigger_b3da0983; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_b3da0983 ON triggers_trigger USING btree (modified_by_id);


--
-- Name: triggers_trigger_contacts_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_contacts_6d82f13d ON triggers_trigger_contacts USING btree (contact_id);


--
-- Name: triggers_trigger_contacts_b10b1f9f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_contacts_b10b1f9f ON triggers_trigger_contacts USING btree (trigger_id);


--
-- Name: triggers_trigger_e93cb7eb; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_e93cb7eb ON triggers_trigger USING btree (created_by_id);


--
-- Name: triggers_trigger_groups_0b1b2ae4; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_groups_0b1b2ae4 ON triggers_trigger_groups USING btree (contactgroup_id);


--
-- Name: triggers_trigger_groups_b10b1f9f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX triggers_trigger_groups_b10b1f9f ON triggers_trigger_groups USING btree (trigger_id);


--
-- Name: users_failedlogin_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX users_failedlogin_user_id ON users_failedlogin USING btree (user_id);


--
-- Name: users_passwordhistory_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX users_passwordhistory_user_id ON users_passwordhistory USING btree (user_id);


--
-- Name: users_recoverytoken_token_like; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX users_recoverytoken_token_like ON users_recoverytoken USING btree (token varchar_pattern_ops);


--
-- Name: users_recoverytoken_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX users_recoverytoken_user_id ON users_recoverytoken USING btree (user_id);


--
-- Name: values_value_0acf093b; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_0acf093b ON values_value USING btree (run_id);


--
-- Name: values_value_4d0a6d0f; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_4d0a6d0f ON values_value USING btree (ruleset_id);


--
-- Name: values_value_6d82f13d; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_6d82f13d ON values_value USING btree (contact_id);


--
-- Name: values_value_91709fb3; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_91709fb3 ON values_value USING btree (location_value_id);


--
-- Name: values_value_9cf869aa; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_9cf869aa ON values_value USING btree (org_id);


--
-- Name: values_value_9ff6aeda; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_9ff6aeda ON values_value USING btree (contact_field_id);


--
-- Name: values_value_rule_uuid_76ab85922190b184_uniq; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX values_value_rule_uuid_76ab85922190b184_uniq ON values_value USING btree (rule_uuid);


--
-- Name: when_contact_groups_changed_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contact_groups_changed_then_update_count_trg AFTER INSERT OR DELETE ON contacts_contactgroup_contacts FOR EACH ROW EXECUTE PROCEDURE update_group_count();


--
-- Name: when_contact_groups_truncate_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_contact_groups_truncate_then_update_count_trg AFTER TRUNCATE ON contacts_contactgroup_contacts FOR EACH STATEMENT EXECUTE PROCEDURE update_group_count();


--
-- Name: when_label_inserted_or_deleted_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_label_inserted_or_deleted_then_update_count_trg AFTER INSERT OR DELETE ON msgs_msg_labels FOR EACH ROW EXECUTE PROCEDURE update_label_count();


--
-- Name: when_labels_truncated_then_update_count_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_labels_truncated_then_update_count_trg AFTER TRUNCATE ON msgs_msg_labels FOR EACH STATEMENT EXECUTE PROCEDURE update_label_count();


--
-- Name: when_msg_updated_then_update_label_counts_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_msg_updated_then_update_label_counts_trg AFTER UPDATE OF visibility ON msgs_msg FOR EACH ROW EXECUTE PROCEDURE update_label_count();


--
-- Name: when_msgs_truncate_then_update_topup_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_msgs_truncate_then_update_topup_trg AFTER TRUNCATE ON msgs_msg FOR EACH STATEMENT EXECUTE PROCEDURE update_topup_used();


--
-- Name: when_msgs_update_then_update_topup_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER when_msgs_update_then_update_topup_trg AFTER INSERT OR DELETE OR UPDATE OF topup_id ON msgs_msg FOR EACH ROW EXECUTE PROCEDURE update_topup_used();


--
-- Name: D7856ce0328a2d48e6fc1da75a134e1a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT "D7856ce0328a2d48e6fc1da75a134e1a" FOREIGN KEY (location_value_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken_org_id_77b477695c02ab21_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_org_id_77b477695c02ab21_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_apitoken_user_id_774044fa21de8279_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_apitoken
    ADD CONSTRAINT api_apitoken_user_id_774044fa21de8279_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhooke_channel_id_3f4bbdf3b1d9dc52_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhooke_channel_id_3f4bbdf3b1d9dc52_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookeven_modified_by_id_2c427a2dc6358334_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookeven_modified_by_id_2c427a2dc6358334_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent_created_by_id_7ebaf1a366420746_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_created_by_id_7ebaf1a366420746_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookevent_org_id_e1907a106ec0f61_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookevent
    ADD CONSTRAINT api_webhookevent_org_id_e1907a106ec0f61_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookres_event_id_46ec3b5f77d8325f_fk_api_webhookevent_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookres_event_id_46ec3b5f77d8325f_fk_api_webhookevent_id FOREIGN KEY (event_id) REFERENCES api_webhookevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookresu_modified_by_id_33992c938ef2495a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresu_modified_by_id_33992c938ef2495a_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_webhookresul_created_by_id_7eeb5bbc1a76a694_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY api_webhookresult
    ADD CONSTRAINT api_webhookresul_created_by_id_7eeb5bbc1a76a694_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_content_type_id_508cf46651277a81_fk_django_content_type_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_permission
    ADD CONSTRAINT auth_content_type_id_508cf46651277a81_fk_django_content_type_id FOREIGN KEY (content_type_id) REFERENCES django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissio_group_id_689710a9a73b7457_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_group_id_689710a9a73b7457_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permission_id_1f49ccbbdc69d2fc_fk_auth_permission_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_group_permissions
    ADD CONSTRAINT auth_group_permission_id_1f49ccbbdc69d2fc_fk_auth_permission_id FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user__permission_id_384b62483d7071f0_fk_auth_permission_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user__permission_id_384b62483d7071f0_fk_auth_permission_id FOREIGN KEY (permission_id) REFERENCES auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups_group_id_33ac548dcf5f8e37_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_33ac548dcf5f8e37_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups_user_id_4b5ed4ffdb8fd9b0_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_4b5ed4ffdb8fd9b0_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permiss_user_id_7f0938558328534a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permiss_user_id_7f0938558328534a_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: authtoken_token_user_id_1d10c57f535fb363_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY authtoken_token
    ADD CONSTRAINT authtoken_token_user_id_1d10c57f535fb363_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: b596316b4c8d5e8b1a642695f578a459; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT b596316b4c8d5e8b1a642695f578a459 FOREIGN KEY (exportmessagestask_id) REFERENCES msgs_exportmessagestask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cam_relative_to_id_64ed25d9daddf398_fk_contacts_contactfield_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT cam_relative_to_id_64ed25d9daddf398_fk_contacts_contactfield_id FOREIGN KEY (relative_to_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaig_event_id_6059f706520cf948_fk_campaigns_campaignevent_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT campaig_event_id_6059f706520cf948_fk_campaigns_campaignevent_id FOREIGN KEY (event_id) REFERENCES campaigns_campaignevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campa_modified_by_id_41d55fb9b8bba7df_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campa_modified_by_id_41d55fb9b8bba7df_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campa_modified_by_id_69154c3fa6c6464a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campa_modified_by_id_69154c3fa6c6464a_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campai_created_by_id_45ec573e6a7b8eb0_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campai_created_by_id_45ec573e6a7b8eb0_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaig_created_by_id_3c593eae2f110b3_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaig_created_by_id_3c593eae2f110b3_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign_id_4a86877cd9f20111_fk_campaigns_campaign_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaign_id_4a86877cd9f20111_fk_campaigns_campaign_id FOREIGN KEY (campaign_id) REFERENCES campaigns_campaign(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaign_org_id_7bf3f205993af9b7_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_campaign_org_id_7bf3f205993af9b7_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_campaigneve_flow_id_46e3d1c67ccdde21_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaignevent
    ADD CONSTRAINT campaigns_campaigneve_flow_id_46e3d1c67ccdde21_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_ev_contact_id_79f6e0f61ab52d46_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_eventfire
    ADD CONSTRAINT campaigns_ev_contact_id_79f6e0f61ab52d46_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: campaigns_group_id_20cbe40ee2180696_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY campaigns_campaign
    ADD CONSTRAINT campaigns_group_id_20cbe40ee2180696_fk_contacts_contactgroup_id FOREIGN KEY (group_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channel_sync_event_id_552d6e8aab4871e1_fk_channels_syncevent_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channel_sync_event_id_552d6e8aab4871e1_fk_channels_syncevent_id FOREIGN KEY (sync_event_id) REFERENCES channels_syncevent(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_ale_channel_id_502b86357e84fad1_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_ale_channel_id_502b86357e84fad1_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert_created_by_id_4d5d82e5368e9597_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_created_by_id_4d5d82e5368e9597_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_alert_modified_by_id_4c8cda51e5df381d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_alert
    ADD CONSTRAINT channels_alert_modified_by_id_4c8cda51e5df381d_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_chan_parent_id_36064d09844a158c_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_chan_parent_id_36064d09844a158c_fk_channels_channel_id FOREIGN KEY (parent_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channe_modified_by_id_62b2d4e6516f60c6_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channe_modified_by_id_62b2d4e6516f60c6_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel_created_by_id_6610297e551df9b4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_created_by_id_6610297e551df9b4_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channel_org_id_46a0e7153fc980b_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channel
    ADD CONSTRAINT channels_channel_org_id_46a0e7153fc980b_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_channellog_msg_id_56c592be3741615b_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_channellog
    ADD CONSTRAINT channels_channellog_msg_id_56c592be3741615b_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syn_channel_id_7259deefb8ce62d0_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syn_channel_id_7259deefb8ce62d0_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_syncev_modified_by_id_4e8922426cef6a42_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_syncev_modified_by_id_4e8922426cef6a42_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: channels_synceven_created_by_id_8c701cdd54f5698_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY channels_syncevent
    ADD CONSTRAINT channels_synceven_created_by_id_8c701cdd54f5698_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: co_contactfield_id_107003fe705d17b6_fk_contacts_contactfield_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT co_contactfield_id_107003fe705d17b6_fk_contacts_contactfield_id FOREIGN KEY (contactfield_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: co_contactgroup_id_278c502545b43b84_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT co_contactgroup_id_278c502545b43b84_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: co_contactgroup_id_7165963c6a634f19_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_query_fields
    ADD CONSTRAINT co_contactgroup_id_7165963c6a634f19_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: co_import_task_id_5350398e66e060f2_fk_csv_imports_importtask_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT co_import_task_id_5350398e66e060f2_fk_csv_imports_importtask_id FOREIGN KEY (import_task_id) REFERENCES csv_imports_importtask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts__group_id_1e1793ae8d8db7fd_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts__group_id_1e1793ae8d8db7fd_fk_contacts_contactgroup_id FOREIGN KEY (group_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_con_channel_id_680f1c6a3e46436c_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_con_channel_id_680f1c6a3e46436c_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_cont_contact_id_1dee76983891f9e_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup_contacts
    ADD CONSTRAINT contacts_cont_contact_id_1dee76983891f9e_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_cont_contact_id_6a14cd898947ebb_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_cont_contact_id_6a14cd898947ebb_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contac_modified_by_id_36030c0844aaddd0_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contac_modified_by_id_36030c0844aaddd0_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contac_modified_by_id_7664e895506510c4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contac_modified_by_id_7664e895506510c4_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact_created_by_id_1ecbe97b0263d19e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contact_created_by_id_1ecbe97b0263d19e_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact_created_by_id_65368d79d1448356_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_created_by_id_65368d79d1448356_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contact_org_id_212b6808b27b8975_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contact
    ADD CONSTRAINT contacts_contact_org_id_212b6808b27b8975_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactfield_org_id_6d343d67f68e5bbc_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactfield
    ADD CONSTRAINT contacts_contactfield_org_id_6d343d67f68e5bbc_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contactgroup_org_id_4c569ecced215497_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contactgroup
    ADD CONSTRAINT contacts_contactgroup_org_id_4c569ecced215497_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_contacturn_org_id_281267463c7173eb_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_contacturn
    ADD CONSTRAINT contacts_contacturn_org_id_281267463c7173eb_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_export_modified_by_id_6ea002332ce10449_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_export_modified_by_id_6ea002332ce10449_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportc_created_by_id_29f74af5cb2b52bd_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportc_created_by_id_29f74af5cb2b52bd_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contacts_exportcontactst_org_id_7d82443698c7b0dc_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY contacts_exportcontactstask
    ADD CONSTRAINT contacts_exportcontactst_org_id_7d82443698c7b0dc_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: djcelery_periodictask_crontab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT djcelery_periodictask_crontab_id_fkey FOREIGN KEY (crontab_id) REFERENCES djcelery_crontabschedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: djcelery_periodictask_interval_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_periodictask
    ADD CONSTRAINT djcelery_periodictask_interval_id_fkey FOREIGN KEY (interval_id) REFERENCES djcelery_intervalschedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: djcelery_taskstate_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY djcelery_taskstate
    ADD CONSTRAINT djcelery_taskstate_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES djcelery_workerstate(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: eeb0ddc0882ec5024ba609c0a2da578c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT eeb0ddc0882ec5024ba609c0a2da578c FOREIGN KEY (exportflowresultstask_id) REFERENCES flows_exportflowresultstask(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: fl_contactgroup_id_2c18111554bb3f34_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT fl_contactgroup_id_2c18111554bb3f34_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_actionlog_run_id_3369b141be764e79_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionlog
    ADD CONSTRAINT flows_actionlog_run_id_3369b141be764e79_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_actionset_flow_id_114b42aa65613713_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_actionset
    ADD CONSTRAINT flows_actionset_flow_id_114b42aa65613713_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflo_modified_by_id_245d7c6dd44b1218_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflo_modified_by_id_245d7c6dd44b1218_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowr_created_by_id_fe9ef751533aec2_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowr_created_by_id_fe9ef751533aec2_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresul_flow_id_673f95f0b8288e24_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask_flows
    ADD CONSTRAINT flows_exportflowresul_flow_id_673f95f0b8288e24_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_exportflowresultst_org_id_687d004b88c4a95d_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_exportflowresultstask
    ADD CONSTRAINT flows_exportflowresultst_org_id_687d004b88c4a95d_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow__flowlabel_id_10704d498ec0685c_fk_flows_flowlabel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow__flowlabel_id_10704d498ec0685c_fk_flows_flowlabel_id FOREIGN KEY (flowlabel_id) REFERENCES flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_created_by_id_43a77db30c244340_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_created_by_id_43a77db30c244340_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_labels_flow_id_5687279f909acaf7_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow_labels
    ADD CONSTRAINT flows_flow_labels_flow_id_5687279f909acaf7_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_modified_by_id_1198e9bc4790ef3a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_modified_by_id_1198e9bc4790ef3a_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_org_id_2988f572a0b88499_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_org_id_2988f572a0b88499_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flow_saved_by_id_3f315b43cdc001_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flow
    ADD CONSTRAINT flows_flow_saved_by_id_3f315b43cdc001_fk_auth_user_id FOREIGN KEY (saved_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabe_parent_id_7e406153150cf37d_fk_flows_flowlabel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabe_parent_id_7e406153150cf37d_fk_flows_flowlabel_id FOREIGN KEY (parent_id) REFERENCES flows_flowlabel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowlabel_org_id_f3717c93b4242c4_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowlabel
    ADD CONSTRAINT flows_flowlabel_org_id_f3717c93b4242c4_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowru_contact_id_7305db203e8aca2f_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowru_contact_id_7305db203e8aca2f_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun_call_id_710603b05c8eae8e_fk_ivr_ivrcall_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_call_id_710603b05c8eae8e_fk_ivr_ivrcall_id FOREIGN KEY (call_id) REFERENCES ivr_ivrcall(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun_flow_id_28f1fcfb7f4856f6_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_flow_id_28f1fcfb7f4856f6_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowrun_start_id_7aad68a947921557_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowrun
    ADD CONSTRAINT flows_flowrun_start_id_7aad68a947921557_fk_flows_flowstart_id FOREIGN KEY (start_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flows_flowstart_id_190f2b17edae43d4_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_groups
    ADD CONSTRAINT flows_flows_flowstart_id_190f2b17edae43d4_fk_flows_flowstart_id FOREIGN KEY (flowstart_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flows_flowstart_id_2d79ad5435e02d63_fk_flows_flowstart_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flows_flowstart_id_2d79ad5435e02d63_fk_flows_flowstart_id FOREIGN KEY (flowstart_id) REFERENCES flows_flowstart(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowst_contact_id_6999c2e63a54b80b_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT flows_flowst_contact_id_6999c2e63a54b80b_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowst_contact_id_75c9d7eac0ef3c8f_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart_contacts
    ADD CONSTRAINT flows_flowst_contact_id_75c9d7eac0ef3c8f_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_created_by_id_76d9f9b94eeb6ed7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_created_by_id_76d9f9b94eeb6ed7_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_flow_id_368fb27924aa80dd_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_flow_id_368fb27924aa80dd_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstart_modified_by_id_330baf525009d6dd_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstart
    ADD CONSTRAINT flows_flowstart_modified_by_id_330baf525009d6dd_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowste_flowstep_id_60796a9cd2be2508_fk_flows_flowstep_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowste_flowstep_id_60796a9cd2be2508_fk_flows_flowstep_id FOREIGN KEY (flowstep_id) REFERENCES flows_flowstep(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep_messages_msg_id_223950c11747ded6_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep_messages
    ADD CONSTRAINT flows_flowstep_messages_msg_id_223950c11747ded6_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowstep_run_id_6957e68e18e66b70_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowstep
    ADD CONSTRAINT flows_flowstep_run_id_6957e68e18e66b70_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowversi_modified_by_id_768a580cc75a82fb_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT flows_flowversi_modified_by_id_768a580cc75a82fb_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowversio_created_by_id_50e12f01017c3519_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT flows_flowversio_created_by_id_50e12f01017c3519_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_flowversion_flow_id_a7316e73678d305_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_flowversion
    ADD CONSTRAINT flows_flowversion_flow_id_a7316e73678d305_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: flows_ruleset_flow_id_5ea82f6f807cb5d7_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY flows_ruleset
    ADD CONSTRAINT flows_ruleset_flow_id_5ea82f6f807cb5d7_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_i_contact_urn_id_2084cbe146270b65_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_i_contact_urn_id_2084cbe146270b65_fk_contacts_contacturn_id FOREIGN KEY (contact_urn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_ivrcall_channel_id_1a52f91ec0cba92e_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_channel_id_1a52f91ec0cba92e_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_ivrcall_contact_id_419ce6de95a060f9_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_contact_id_419ce6de95a060f9_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_ivrcall_created_by_id_6b562edc4347843a_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_created_by_id_6b562edc4347843a_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_ivrcall_flow_id_8be421ccbc6ab4_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_flow_id_8be421ccbc6ab4_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_ivrcall_modified_by_id_574e7f801edef74c_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_modified_by_id_574e7f801edef74c_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ivr_ivrcall_org_id_35bf0364666e6b1f_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ivr_ivrcall
    ADD CONSTRAINT ivr_ivrcall_org_id_35bf0364666e6b1f_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: loca_boundary_id_17d6c0f894dfa788_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT loca_boundary_id_17d6c0f894dfa788_fk_locations_adminboundary_id FOREIGN KEY (boundary_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locati_parent_id_41e8ac6845aa81af_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_adminboundary
    ADD CONSTRAINT locati_parent_id_41e8ac6845aa81af_fk_locations_adminboundary_id FOREIGN KEY (parent_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_bound_modified_by_id_3988b5c65cd8bbf2_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_bound_modified_by_id_3988b5c65cd8bbf2_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_bounda_created_by_id_3a1891421ba51f48_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_bounda_created_by_id_3a1891421ba51f48_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: locations_boundaryalias_org_id_7f54533484973f5f_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations_boundaryalias
    ADD CONSTRAINT locations_boundaryalias_org_id_7f54533484973f5f_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ms_contactgroup_id_20a9b0f24aa76602_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask_groups
    ADD CONSTRAINT ms_contactgroup_id_20a9b0f24aa76602_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ms_contactgroup_id_69fa68e0f5da4933_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT ms_contactgroup_id_69fa68e0f5da4933_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs__contact_urn_id_59810d7ced4679b1_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs__contact_urn_id_59810d7ced4679b1_fk_contacts_contacturn_id FOREIGN KEY (contact_urn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_b_contacturn_id_6650304a8351a905_fk_contacts_contacturn_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_b_contacturn_id_6650304a8351a905_fk_contacts_contacturn_id FOREIGN KEY (contacturn_id) REFERENCES contacts_contacturn(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadc_schedule_id_18fb3a4522250d_fk_schedules_schedule_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadc_schedule_id_18fb3a4522250d_fk_schedules_schedule_id FOREIGN KEY (schedule_id) REFERENCES schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadca_broadcast_id_273686d8dda14f12_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_groups
    ADD CONSTRAINT msgs_broadca_broadcast_id_273686d8dda14f12_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadca_broadcast_id_5b4fa96ddab8e374_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_urns
    ADD CONSTRAINT msgs_broadca_broadcast_id_5b4fa96ddab8e374_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadca_broadcast_id_62a015996c701a93_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadca_broadcast_id_62a015996c701a93_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadca_channel_id_20eff13de920a190_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadca_channel_id_20eff13de920a190_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadca_contact_id_24f586819443ac38_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast_contacts
    ADD CONSTRAINT msgs_broadca_contact_id_24f586819443ac38_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_created_by_id_9e977c111c9eed8_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_created_by_id_9e977c111c9eed8_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_modified_by_id_70f33f6bac4b05fe_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_modified_by_id_70f33f6bac4b05fe_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_org_id_44bb43690abeb62f_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_org_id_44bb43690abeb62f_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_broadcast_parent_id_3b06e0868b0e47b0_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_broadcast
    ADD CONSTRAINT msgs_broadcast_parent_id_3b06e0868b0e47b0_fk_msgs_broadcast_id FOREIGN KEY (parent_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_call_channel_id_50592d73e235a8c0_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT msgs_call_channel_id_50592d73e235a8c0_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_call_contact_id_158445ad438f5a67_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT msgs_call_contact_id_158445ad438f5a67_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_call_created_by_id_2a586032f24d628_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT msgs_call_created_by_id_2a586032f24d628_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_call_modified_by_id_78983bab53954452_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT msgs_call_modified_by_id_78983bab53954452_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_call_org_id_f51c8e77fe5007f_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_call
    ADD CONSTRAINT msgs_call_org_id_f51c8e77fe5007f_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessa_created_by_id_471f7a032fa4318f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessa_created_by_id_471f7a032fa4318f_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessa_modified_by_id_65c0a1ac1ec6ffd_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessa_modified_by_id_65c0a1ac1ec6ffd_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagest_label_id_4e6ef73cac56278e_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagest_label_id_4e6ef73cac56278e_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_exportmessagestask_org_id_45aa71572acdee88_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_exportmessagestask
    ADD CONSTRAINT msgs_exportmessagestask_org_id_45aa71572acdee88_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label_created_by_id_fcd217a496d61b5_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_created_by_id_fcd217a496d61b5_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label_folder_id_1fe88e1f66fca0b9_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_folder_id_1fe88e1f66fca0b9_fk_msgs_label_id FOREIGN KEY (folder_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label_modified_by_id_17b1c8500c7961a1_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_modified_by_id_17b1c8500c7961a1_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_label_org_id_72495077cc142a8c_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_label
    ADD CONSTRAINT msgs_label_org_id_72495077cc142a8c_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_broadcast_id_4fac17980f6cfb26_fk_msgs_broadcast_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_broadcast_id_4fac17980f6cfb26_fk_msgs_broadcast_id FOREIGN KEY (broadcast_id) REFERENCES msgs_broadcast(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_channel_id_4e0904d359b1c974_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_channel_id_4e0904d359b1c974_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_contact_id_4d2b08b41a2e4165_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_contact_id_4d2b08b41a2e4165_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_labels_label_id_57f599ef4afb99dc_fk_msgs_label_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_label_id_57f599ef4afb99dc_fk_msgs_label_id FOREIGN KEY (label_id) REFERENCES msgs_label(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_labels_msg_id_6388492dcafc37d1_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg_labels
    ADD CONSTRAINT msgs_msg_labels_msg_id_6388492dcafc37d1_fk_msgs_msg_id FOREIGN KEY (msg_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_org_id_26000d4f3e2df035_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_org_id_26000d4f3e2df035_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_response_to_id_45a3c38a6499df3a_fk_msgs_msg_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_response_to_id_45a3c38a6499df3a_fk_msgs_msg_id FOREIGN KEY (response_to_id) REFERENCES msgs_msg(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: msgs_msg_topup_id_5229233211d7a35f_fk_orgs_topup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY msgs_msg
    ADD CONSTRAINT msgs_msg_topup_id_5229233211d7a35f_fk_orgs_topup_id FOREIGN KEY (topup_id) REFERENCES orgs_topup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs__country_id_4d13c8b06b539c33_fk_locations_adminboundary_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs__country_id_4d13c8b06b539c33_fk_locations_adminboundary_id FOREIGN KEY (country_id) REFERENCES locations_adminboundary(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditaler_modified_by_id_60a9e9bf88b281ef_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditaler_modified_by_id_60a9e9bf88b281ef_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert_created_by_id_65ec03c75f0bcc3b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_created_by_id_65ec03c75f0bcc3b_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_creditalert_org_id_16cf0d6d4f0351e4_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_creditalert
    ADD CONSTRAINT orgs_creditalert_org_id_16cf0d6d4f0351e4_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation_created_by_id_4ae7217040b478ae_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_created_by_id_4ae7217040b478ae_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation_modified_by_id_45203d979e7a2528_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_modified_by_id_45203d979e7a2528_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_invitation_org_id_7576921ea005d393_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_invitation
    ADD CONSTRAINT orgs_invitation_org_id_7576921ea005d393_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_language_created_by_id_5c7506ea75406e8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_created_by_id_5c7506ea75406e8b_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_language_modified_by_id_1c5f5a7cf156909f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_modified_by_id_1c5f5a7cf156909f_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_language_org_id_5eed730ebdc71ccc_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_language
    ADD CONSTRAINT orgs_language_org_id_5eed730ebdc71ccc_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_o_primary_language_id_38dfc7d8636f176f_fk_orgs_language_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_o_primary_language_id_38dfc7d8636f176f_fk_orgs_language_id FOREIGN KEY (primary_language_id) REFERENCES orgs_language(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_administrator_user_id_54ffec6ceb234cad_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrator_user_id_54ffec6ceb234cad_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_administrators_org_id_4a63c5e1e9112a2b_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_administrators
    ADD CONSTRAINT orgs_org_administrators_org_id_4a63c5e1e9112a2b_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_created_by_id_7dc2cdc9ca6bb3ce_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_created_by_id_7dc2cdc9ca6bb3ce_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_editors_org_id_75f9ebdda677f6de_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_org_id_75f9ebdda677f6de_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_editors_user_id_4063d036091838ca_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_editors
    ADD CONSTRAINT orgs_org_editors_user_id_4063d036091838ca_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_modified_by_id_5b12a551eb261ef8_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org
    ADD CONSTRAINT orgs_org_modified_by_id_5b12a551eb261ef8_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_viewers_org_id_24f887033e669cad_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_org_id_24f887033e669cad_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_org_viewers_user_id_646d8ba9c4c29c05_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_org_viewers
    ADD CONSTRAINT orgs_org_viewers_user_id_646d8ba9c4c29c05_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup_created_by_id_1f04590f31ba1440_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_created_by_id_1f04590f31ba1440_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup_modified_by_id_3aaf3f8eee3fc0ba_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_modified_by_id_3aaf3f8eee3fc0ba_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_topup_org_id_5e04c4c8e3934ce7_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_topup
    ADD CONSTRAINT orgs_topup_org_id_5e04c4c8e3934ce7_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: orgs_usersettings_user_id_78faf346ec8d78dc_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY orgs_usersettings
    ADD CONSTRAINT orgs_usersettings_user_id_78faf346ec8d78dc_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_lead_created_by_id_40780a2661753d23_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT public_lead_created_by_id_40780a2661753d23_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_lead_modified_by_id_36cb762c3680dad7_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_lead
    ADD CONSTRAINT public_lead_modified_by_id_36cb762c3680dad7_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_video_created_by_id_4b8ef5a7b2e1f49f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT public_video_created_by_id_4b8ef5a7b2e1f49f_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public_video_modified_by_id_7ac9b608d090508d_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public_video
    ADD CONSTRAINT public_video_modified_by_id_7ac9b608d090508d_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: reports_report_created_by_id_28c148ab505e7ab4_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_created_by_id_28c148ab505e7ab4_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: reports_report_modified_by_id_6264be3e1f63ff2e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_modified_by_id_6264be3e1f63ff2e_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: reports_report_org_id_6832e716a63b998d_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports_report
    ADD CONSTRAINT reports_report_org_id_6832e716a63b998d_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedules_sched_modified_by_id_34628494f4adbdfa_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT schedules_sched_modified_by_id_34628494f4adbdfa_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: schedules_schedu_created_by_id_47fe63e6a06c8b80_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schedules_schedule
    ADD CONSTRAINT schedules_schedu_created_by_id_47fe63e6a06c8b80_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: tr_contactgroup_id_442b91e248f15275_fk_contacts_contactgroup_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT tr_contactgroup_id_442b91e248f15275_fk_contacts_contactgroup_id FOREIGN KEY (contactgroup_id) REFERENCES contacts_contactgroup(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers__schedule_id_759d0ed6fd42cf01_fk_schedules_schedule_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers__schedule_id_759d0ed6fd42cf01_fk_schedules_schedule_id FOREIGN KEY (schedule_id) REFERENCES schedules_schedule(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_tri_channel_id_62a982d8a1113f4a_fk_channels_channel_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_tri_channel_id_62a982d8a1113f4a_fk_channels_channel_id FOREIGN KEY (channel_id) REFERENCES channels_channel(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_tri_trigger_id_177264725d510da9_fk_triggers_trigger_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_groups
    ADD CONSTRAINT triggers_tri_trigger_id_177264725d510da9_fk_triggers_trigger_id FOREIGN KEY (trigger_id) REFERENCES triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_tri_trigger_id_2c17f5afa89ff0da_fk_triggers_trigger_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_tri_trigger_id_2c17f5afa89ff0da_fk_triggers_trigger_id FOREIGN KEY (trigger_id) REFERENCES triggers_trigger(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trig_contact_id_786a177482e4a1a_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger_contacts
    ADD CONSTRAINT triggers_trig_contact_id_786a177482e4a1a_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigge_modified_by_id_59575750057f43b8_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigge_modified_by_id_59575750057f43b8_fk_auth_user_id FOREIGN KEY (modified_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_created_by_id_599bd0e8c1cb7a1e_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_created_by_id_599bd0e8c1cb7a1e_fk_auth_user_id FOREIGN KEY (created_by_id) REFERENCES auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_flow_id_3c5d221c435299b8_fk_flows_flow_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_flow_id_3c5d221c435299b8_fk_flows_flow_id FOREIGN KEY (flow_id) REFERENCES flows_flow(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: triggers_trigger_org_id_13a5b26e0046d23d_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY triggers_trigger
    ADD CONSTRAINT triggers_trigger_org_id_13a5b26e0046d23d_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: v_contact_field_id_7f4bfdc5a455f696_fk_contacts_contactfield_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT v_contact_field_id_7f4bfdc5a455f696_fk_contacts_contactfield_id FOREIGN KEY (contact_field_id) REFERENCES contacts_contactfield(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value_contact_id_40ea694526963313_fk_contacts_contact_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_contact_id_40ea694526963313_fk_contacts_contact_id FOREIGN KEY (contact_id) REFERENCES contacts_contact(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value_org_id_7a23288fb4cdf1ed_fk_orgs_org_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_org_id_7a23288fb4cdf1ed_fk_orgs_org_id FOREIGN KEY (org_id) REFERENCES orgs_org(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value_ruleset_id_301e2637f947a477_fk_flows_ruleset_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_ruleset_id_301e2637f947a477_fk_flows_ruleset_id FOREIGN KEY (ruleset_id) REFERENCES flows_ruleset(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: values_value_run_id_725c12f9420b93a2_fk_flows_flowrun_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY values_value
    ADD CONSTRAINT values_value_run_id_725c12f9420b93a2_fk_flows_flowrun_id FOREIGN KEY (run_id) REFERENCES flows_flowrun(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: public; Type: ACL; Schema: -; Owner: -
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

