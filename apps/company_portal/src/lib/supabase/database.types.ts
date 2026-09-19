export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      account_deletion_requests: {
        Row: {
          cancelled_at: string | null
          person_id: string
          reason: string | null
          requested_at: string
          scheduled_for: string
        }
        Insert: {
          cancelled_at?: string | null
          person_id: string
          reason?: string | null
          requested_at?: string
          scheduled_for: string
        }
        Update: {
          cancelled_at?: string | null
          person_id?: string
          reason?: string | null
          requested_at?: string
          scheduled_for?: string
        }
        Relationships: [
          {
            foreignKeyName: "account_deletion_requests_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: true
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_client_contacts: {
        Row: {
          client_id: string
          created_at: string
          email: string | null
          id: string
          is_primary: boolean
          name: string
          notes: string | null
          phone: string | null
          title: string | null
        }
        Insert: {
          client_id: string
          created_at?: string
          email?: string | null
          id?: string
          is_primary?: boolean
          name: string
          notes?: string | null
          phone?: string | null
          title?: string | null
        }
        Update: {
          client_id?: string
          created_at?: string
          email?: string | null
          id?: string
          is_primary?: boolean
          name?: string
          notes?: string | null
          phone?: string | null
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agency_client_contacts_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_clients: {
        Row: {
          agency_id: string
          client_company_id: string | null
          created_at: string
          created_by: string | null
          departments: string[]
          id: string
          industry: string | null
          link_status: string
          locations: string[]
          name: string
          notes: string | null
          owner_id: string | null
          relationship_status: string
          requested_company_id: string | null
          updated_at: string
          website: string | null
        }
        Insert: {
          agency_id: string
          client_company_id?: string | null
          created_at?: string
          created_by?: string | null
          departments?: string[]
          id?: string
          industry?: string | null
          link_status?: string
          locations?: string[]
          name: string
          notes?: string | null
          owner_id?: string | null
          relationship_status?: string
          requested_company_id?: string | null
          updated_at?: string
          website?: string | null
        }
        Update: {
          agency_id?: string
          client_company_id?: string | null
          created_at?: string
          created_by?: string | null
          departments?: string[]
          id?: string
          industry?: string | null
          link_status?: string
          locations?: string[]
          name?: string
          notes?: string | null
          owner_id?: string | null
          relationship_status?: string
          requested_company_id?: string | null
          updated_at?: string
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agency_clients_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agency_clients_client_company_id_fkey"
            columns: ["client_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agency_clients_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agency_clients_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agency_clients_requested_company_id_fkey"
            columns: ["requested_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      application_events: {
        Row: {
          actor_id: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          application_id: string
          event_type: Database["public"]["Enums"]["application_event_type"]
          from_stage_id: string | null
          from_state: Database["public"]["Enums"]["application_state"] | null
          id: number
          metadata: Json
          occurred_at: string
          reason: string | null
          to_stage_id: string | null
          to_state: Database["public"]["Enums"]["application_state"] | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          application_id: string
          event_type: Database["public"]["Enums"]["application_event_type"]
          from_stage_id?: string | null
          from_state?: Database["public"]["Enums"]["application_state"] | null
          id?: number
          metadata?: Json
          occurred_at?: string
          reason?: string | null
          to_stage_id?: string | null
          to_state?: Database["public"]["Enums"]["application_state"] | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: Database["public"]["Enums"]["actor_type"]
          application_id?: string
          event_type?: Database["public"]["Enums"]["application_event_type"]
          from_stage_id?: string | null
          from_state?: Database["public"]["Enums"]["application_state"] | null
          id?: number
          metadata?: Json
          occurred_at?: string
          reason?: string | null
          to_stage_id?: string | null
          to_state?: Database["public"]["Enums"]["application_state"] | null
        }
        Relationships: [
          {
            foreignKeyName: "application_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_events_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      application_notes: {
        Row: {
          application_id: string
          author_id: string | null
          body: string
          company_id: string
          created_at: string
          id: string
        }
        Insert: {
          application_id: string
          author_id?: string | null
          body: string
          company_id: string
          created_at?: string
          id?: string
        }
        Update: {
          application_id?: string
          author_id?: string | null
          body?: string
          company_id?: string
          created_at?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_notes_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_notes_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_notes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      applications: {
        Row: {
          answers: Json
          applied_at: string
          applied_via: string
          closed_at: string | null
          company_id: string
          cover_note: string | null
          first_viewed_at: string | null
          id: string
          identity_snapshot: Json
          is_archived: boolean | null
          job_id: string
          last_activity_at: string
          match_score: number | null
          person_id: string
          rejected_by: string | null
          rejection_reason: string | null
          resume_document_id: string | null
          stage_id: string | null
          state: Database["public"]["Enums"]["application_state"]
          withdrawal_reason: string | null
          work_identity_id: string
        }
        Insert: {
          answers?: Json
          applied_at?: string
          applied_via?: string
          closed_at?: string | null
          company_id: string
          cover_note?: string | null
          first_viewed_at?: string | null
          id?: string
          identity_snapshot?: Json
          is_archived?: boolean | null
          job_id: string
          last_activity_at?: string
          match_score?: number | null
          person_id: string
          rejected_by?: string | null
          rejection_reason?: string | null
          resume_document_id?: string | null
          stage_id?: string | null
          state?: Database["public"]["Enums"]["application_state"]
          withdrawal_reason?: string | null
          work_identity_id: string
        }
        Update: {
          answers?: Json
          applied_at?: string
          applied_via?: string
          closed_at?: string | null
          company_id?: string
          cover_note?: string | null
          first_viewed_at?: string | null
          id?: string
          identity_snapshot?: Json
          is_archived?: boolean | null
          job_id?: string
          last_activity_at?: string
          match_score?: number | null
          person_id?: string
          rejected_by?: string | null
          rejection_reason?: string | null
          resume_document_id?: string | null
          stage_id?: string | null
          state?: Database["public"]["Enums"]["application_state"]
          withdrawal_reason?: string | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "applications_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_rejected_by_fkey"
            columns: ["rejected_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_resume_document_id_fkey"
            columns: ["resume_document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_stage_id_fkey"
            columns: ["stage_id"]
            isOneToOne: false
            referencedRelation: "job_stages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      assessments: {
        Row: {
          application_id: string
          completed_at: string | null
          created_at: string
          due_at: string | null
          external_url: string | null
          id: string
          job_id: string
          kind: string
          max_score: number | null
          name: string
          provider: string | null
          result: Json
          score: number | null
          sent_at: string | null
        }
        Insert: {
          application_id: string
          completed_at?: string | null
          created_at?: string
          due_at?: string | null
          external_url?: string | null
          id?: string
          job_id: string
          kind?: string
          max_score?: number | null
          name: string
          provider?: string | null
          result?: Json
          score?: number | null
          sent_at?: string | null
        }
        Update: {
          application_id?: string
          completed_at?: string | null
          created_at?: string
          due_at?: string | null
          external_url?: string | null
          id?: string
          job_id?: string
          kind?: string
          max_score?: number | null
          name?: string
          provider?: string | null
          result?: Json
          score?: number | null
          sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assessments_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assessments_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      assignment_billing: {
        Row: {
          assignment_id: string
          bill_period: Database["public"]["Enums"]["pay_period"]
          bill_rate: number
          currency: string
          note: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          assignment_id: string
          bill_period: Database["public"]["Enums"]["pay_period"]
          bill_rate: number
          currency: string
          note?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          assignment_id?: string
          bill_period?: Database["public"]["Enums"]["pay_period"]
          bill_rate?: number
          currency?: string
          note?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assignment_billing_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: true
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignment_billing_currency_currency_fk"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "assignment_billing_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      assignments: {
        Row: {
          activated_at: string | null
          agreement: Json
          application_id: string | null
          client_company_id: string | null
          client_id: string | null
          company_id: string
          consent_id: string | null
          created_at: string
          created_by: string | null
          currency: string
          decline_reason: string | null
          employment_id: string | null
          employment_type: string
          end_date: string | null
          end_reason: string | null
          ended_at: string | null
          ending_notice_sent_at: string | null
          id: string
          job_id: string | null
          job_order_id: string | null
          location_id: string | null
          location_text: string | null
          offer_expires_at: string | null
          offered_at: string | null
          overtime_policy_id: string | null
          pay_frequency: string
          pay_period: Database["public"]["Enums"]["pay_period"]
          pay_rate: number
          person_id: string
          requirement_id: string
          responded_at: string | null
          source: string
          start_date: string
          status: string
          submission_id: string | null
          supervisor_id: string | null
          timezone: string
          title: string
          updated_at: string
          work_identity_id: string
          work_type: Database["public"]["Enums"]["work_type"]
        }
        Insert: {
          activated_at?: string | null
          agreement?: Json
          application_id?: string | null
          client_company_id?: string | null
          client_id?: string | null
          company_id: string
          consent_id?: string | null
          created_at?: string
          created_by?: string | null
          currency: string
          decline_reason?: string | null
          employment_id?: string | null
          employment_type: string
          end_date?: string | null
          end_reason?: string | null
          ended_at?: string | null
          ending_notice_sent_at?: string | null
          id?: string
          job_id?: string | null
          job_order_id?: string | null
          location_id?: string | null
          location_text?: string | null
          offer_expires_at?: string | null
          offered_at?: string | null
          overtime_policy_id?: string | null
          pay_frequency: string
          pay_period: Database["public"]["Enums"]["pay_period"]
          pay_rate: number
          person_id: string
          requirement_id: string
          responded_at?: string | null
          source: string
          start_date: string
          status?: string
          submission_id?: string | null
          supervisor_id?: string | null
          timezone: string
          title: string
          updated_at?: string
          work_identity_id: string
          work_type: Database["public"]["Enums"]["work_type"]
        }
        Update: {
          activated_at?: string | null
          agreement?: Json
          application_id?: string | null
          client_company_id?: string | null
          client_id?: string | null
          company_id?: string
          consent_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          decline_reason?: string | null
          employment_id?: string | null
          employment_type?: string
          end_date?: string | null
          end_reason?: string | null
          ended_at?: string | null
          ending_notice_sent_at?: string | null
          id?: string
          job_id?: string | null
          job_order_id?: string | null
          location_id?: string | null
          location_text?: string | null
          offer_expires_at?: string | null
          offered_at?: string | null
          overtime_policy_id?: string | null
          pay_frequency?: string
          pay_period?: Database["public"]["Enums"]["pay_period"]
          pay_rate?: number
          person_id?: string
          requirement_id?: string
          responded_at?: string | null
          source?: string
          start_date?: string
          status?: string
          submission_id?: string | null
          supervisor_id?: string | null
          timezone?: string
          title?: string
          updated_at?: string
          work_identity_id?: string
          work_type?: Database["public"]["Enums"]["work_type"]
        }
        Relationships: [
          {
            foreignKeyName: "assignments_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_client_company_id_fkey"
            columns: ["client_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_consent_id_fkey"
            columns: ["consent_id"]
            isOneToOne: false
            referencedRelation: "candidate_consents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_currency_currency_fk"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "assignments_employment_id_fkey"
            columns: ["employment_id"]
            isOneToOne: false
            referencedRelation: "employments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_job_order_id_fkey"
            columns: ["job_order_id"]
            isOneToOne: false
            referencedRelation: "job_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_overtime_policy_id_fkey"
            columns: ["overtime_policy_id"]
            isOneToOne: false
            referencedRelation: "overtime_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_requirement_id_fkey"
            columns: ["requirement_id"]
            isOneToOne: false
            referencedRelation: "workforce_requirements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "candidate_submissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_exceptions: {
        Row: {
          attendance_id: string
          created_at: string
          detail: string | null
          id: string
          kind: string
          minutes: number | null
          resolution_note: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: string
        }
        Insert: {
          attendance_id: string
          created_at?: string
          detail?: string | null
          id?: string
          kind: string
          minutes?: number | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
        }
        Update: {
          attendance_id?: string
          created_at?: string
          detail?: string | null
          id?: string
          kind?: string
          minutes?: number | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_exceptions_attendance_id_fkey"
            columns: ["attendance_id"]
            isOneToOne: false
            referencedRelation: "attendance_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_exceptions_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_records: {
        Row: {
          assignment_id: string
          break_minutes: number
          check_in_at: string | null
          check_in_geo: unknown
          check_in_method: string | null
          check_out_at: string | null
          check_out_method: string | null
          created_at: string
          id: string
          payable_minutes: number | null
          person_id: string
          review_note: string | null
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          scheduled_end: string
          scheduled_start: string
          shift_id: string
          shift_worker_id: string
          status: string
          updated_at: string
          worked_minutes: number | null
        }
        Insert: {
          assignment_id: string
          break_minutes?: number
          check_in_at?: string | null
          check_in_geo?: unknown
          check_in_method?: string | null
          check_out_at?: string | null
          check_out_method?: string | null
          created_at?: string
          id?: string
          payable_minutes?: number | null
          person_id: string
          review_note?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          scheduled_end: string
          scheduled_start: string
          shift_id: string
          shift_worker_id: string
          status: string
          updated_at?: string
          worked_minutes?: number | null
        }
        Update: {
          assignment_id?: string
          break_minutes?: number
          check_in_at?: string | null
          check_in_geo?: unknown
          check_in_method?: string | null
          check_out_at?: string | null
          check_out_method?: string | null
          created_at?: string
          id?: string
          payable_minutes?: number | null
          person_id?: string
          review_note?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          scheduled_end?: string
          scheduled_start?: string
          shift_id?: string
          shift_worker_id?: string
          status?: string
          updated_at?: string
          worked_minutes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "attendance_records_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shifts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_shift_worker_id_fkey"
            columns: ["shift_worker_id"]
            isOneToOne: true
            referencedRelation: "shift_workers"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_id: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          company_id: string | null
          id: number
          ip_hash: string | null
          metadata: Json
          occurred_at: string
          subject_id: string | null
          subject_type: string
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          actor_type: Database["public"]["Enums"]["actor_type"]
          company_id?: string | null
          id?: number
          ip_hash?: string | null
          metadata?: Json
          occurred_at?: string
          subject_id?: string | null
          subject_type: string
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          actor_type?: Database["public"]["Enums"]["actor_type"]
          company_id?: string | null
          id?: number
          ip_hash?: string | null
          metadata?: Json
          occurred_at?: string
          subject_id?: string | null
          subject_type?: string
          user_agent?: string | null
        }
        Relationships: []
      }
      automated_decision_log: {
        Row: {
          company_id: string | null
          decision_kind: string
          engine_version: string
          human_reviewed: boolean
          id: number
          job_id: string | null
          occurred_at: string
          outcome: Json
          person_id: string | null
          review_requested_at: string | null
          reviewed_at: string | null
        }
        Insert: {
          company_id?: string | null
          decision_kind: string
          engine_version: string
          human_reviewed?: boolean
          id?: number
          job_id?: string | null
          occurred_at?: string
          outcome: Json
          person_id?: string | null
          review_requested_at?: string | null
          reviewed_at?: string | null
        }
        Update: {
          company_id?: string | null
          decision_kind?: string
          engine_version?: string
          human_reviewed?: boolean
          id?: number
          job_id?: string | null
          occurred_at?: string
          outcome?: Json
          person_id?: string | null
          review_requested_at?: string | null
          reviewed_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "automated_decision_log_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "automated_decision_log_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "automated_decision_log_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_records: {
        Row: {
          agency_id: string
          amount: number
          assignment_id: string
          bill_rate: number
          client_company_id: string | null
          client_id: string | null
          created_at: string
          currency: string
          id: string
          quantity: number
          status: string
          timesheet_id: string
          unit: string
          updated_at: string
        }
        Insert: {
          agency_id: string
          amount: number
          assignment_id: string
          bill_rate: number
          client_company_id?: string | null
          client_id?: string | null
          created_at?: string
          currency: string
          id?: string
          quantity: number
          status?: string
          timesheet_id: string
          unit: string
          updated_at?: string
        }
        Update: {
          agency_id?: string
          amount?: number
          assignment_id?: string
          bill_rate?: number
          client_company_id?: string | null
          client_id?: string | null
          created_at?: string
          currency?: string
          id?: string
          quantity?: number
          status?: string
          timesheet_id?: string
          unit?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_records_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_records_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_records_client_company_id_fkey"
            columns: ["client_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_records_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_records_currency_currency_fk"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "billing_records_timesheet_id_fkey"
            columns: ["timesheet_id"]
            isOneToOne: true
            referencedRelation: "timesheets"
            referencedColumns: ["id"]
          },
        ]
      }
      blocks: {
        Row: {
          created_at: string
          person_id: string
          reason: string | null
          target_id: string
          target_type: string
        }
        Insert: {
          created_at?: string
          person_id: string
          reason?: string | null
          target_id: string
          target_type: string
        }
        Update: {
          created_at?: string
          person_id?: string
          reason?: string | null
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocks_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      candidate_consent_events: {
        Row: {
          actor_id: string | null
          actor_type: string
          consent_id: string
          from_status: string | null
          id: number
          occurred_at: string
          reason: string | null
          to_status: string
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          consent_id: string
          from_status?: string | null
          id?: never
          occurred_at?: string
          reason?: string | null
          to_status: string
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          consent_id?: string
          from_status?: string | null
          id?: never
          occurred_at?: string
          reason?: string | null
          to_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidate_consent_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_consent_events_consent_id_fkey"
            columns: ["consent_id"]
            isOneToOne: false
            referencedRelation: "candidate_consents"
            referencedColumns: ["id"]
          },
        ]
      }
      candidate_consents: {
        Row: {
          agency_id: string
          client_id: string
          decline_reason: string | null
          expires_at: string | null
          id: string
          information_scope: string[]
          job_order_id: string
          message: string | null
          person_id: string
          purpose: string
          recruiter_id: string | null
          request_expires_at: string
          requested_at: string
          responded_at: string | null
          revoke_reason: string | null
          revoked_at: string | null
          status: string
          terms: Json
          updated_at: string
          valid_days: number
          work_identity_id: string
        }
        Insert: {
          agency_id: string
          client_id: string
          decline_reason?: string | null
          expires_at?: string | null
          id?: string
          information_scope: string[]
          job_order_id: string
          message?: string | null
          person_id: string
          purpose?: string
          recruiter_id?: string | null
          request_expires_at?: string
          requested_at?: string
          responded_at?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          status?: string
          terms: Json
          updated_at?: string
          valid_days?: number
          work_identity_id: string
        }
        Update: {
          agency_id?: string
          client_id?: string
          decline_reason?: string | null
          expires_at?: string | null
          id?: string
          information_scope?: string[]
          job_order_id?: string
          message?: string | null
          person_id?: string
          purpose?: string
          recruiter_id?: string | null
          request_expires_at?: string
          requested_at?: string
          responded_at?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          status?: string
          terms?: Json
          updated_at?: string
          valid_days?: number
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidate_consents_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_consents_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_consents_job_order_id_fkey"
            columns: ["job_order_id"]
            isOneToOne: false
            referencedRelation: "job_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_consents_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_consents_recruiter_id_fkey"
            columns: ["recruiter_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_consents_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      candidate_invitations: {
        Row: {
          company_id: string
          decline_reason: string | null
          expires_at: string
          id: string
          job_id: string
          message: string | null
          person_id: string
          responded_at: string | null
          response: string | null
          sent_at: string
          sent_by: string | null
          viewed_at: string | null
          work_identity_id: string | null
        }
        Insert: {
          company_id: string
          decline_reason?: string | null
          expires_at?: string
          id?: string
          job_id: string
          message?: string | null
          person_id: string
          responded_at?: string | null
          response?: string | null
          sent_at?: string
          sent_by?: string | null
          viewed_at?: string | null
          work_identity_id?: string | null
        }
        Update: {
          company_id?: string
          decline_reason?: string | null
          expires_at?: string
          id?: string
          job_id?: string
          message?: string | null
          person_id?: string
          responded_at?: string | null
          response?: string | null
          sent_at?: string
          sent_by?: string | null
          viewed_at?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "candidate_invitations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_sent_by_fkey"
            columns: ["sent_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_invitations_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      candidate_submission_events: {
        Row: {
          actor_id: string | null
          from_status: string | null
          id: number
          occurred_at: string
          reason: string | null
          submission_id: string
          to_status: string
        }
        Insert: {
          actor_id?: string | null
          from_status?: string | null
          id?: never
          occurred_at?: string
          reason?: string | null
          submission_id: string
          to_status: string
        }
        Update: {
          actor_id?: string | null
          from_status?: string | null
          id?: never
          occurred_at?: string
          reason?: string | null
          submission_id?: string
          to_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidate_submission_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submission_events_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "candidate_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      candidate_submissions: {
        Row: {
          agency_id: string
          application_id: string | null
          client_id: string
          client_response: string | null
          consent_id: string
          id: string
          job_order_id: string
          person_id: string
          recruiter_id: string | null
          recruiter_note: string | null
          rejection_reason: string | null
          snapshot: Json
          status: string
          submitted_at: string
          updated_at: string
          work_identity_id: string
        }
        Insert: {
          agency_id: string
          application_id?: string | null
          client_id: string
          client_response?: string | null
          consent_id: string
          id?: string
          job_order_id: string
          person_id: string
          recruiter_id?: string | null
          recruiter_note?: string | null
          rejection_reason?: string | null
          snapshot: Json
          status?: string
          submitted_at?: string
          updated_at?: string
          work_identity_id: string
        }
        Update: {
          agency_id?: string
          application_id?: string | null
          client_id?: string
          client_response?: string | null
          consent_id?: string
          id?: string
          job_order_id?: string
          person_id?: string
          recruiter_id?: string | null
          recruiter_note?: string | null
          rejection_reason?: string | null
          snapshot?: Json
          status?: string
          submitted_at?: string
          updated_at?: string
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidate_submissions_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submissions_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submissions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submissions_consent_id_fkey"
            columns: ["consent_id"]
            isOneToOne: true
            referencedRelation: "candidate_consents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submissions_job_order_id_fkey"
            columns: ["job_order_id"]
            isOneToOne: false
            referencedRelation: "job_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submissions_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submissions_recruiter_id_fkey"
            columns: ["recruiter_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidate_submissions_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      career_goals: {
        Row: {
          created_at: string
          goal_text: string | null
          id: string
          person_id: string
          priority: number
          profession_id: string | null
          target_countries: string[]
          target_currency: string | null
          target_pay_amount: number | null
          target_pay_period: Database["public"]["Enums"]["pay_period"] | null
          work_identity_id: string
        }
        Insert: {
          created_at?: string
          goal_text?: string | null
          id?: string
          person_id: string
          priority?: number
          profession_id?: string | null
          target_countries?: string[]
          target_currency?: string | null
          target_pay_amount?: number | null
          target_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          work_identity_id: string
        }
        Update: {
          created_at?: string
          goal_text?: string | null
          id?: string
          person_id?: string
          priority?: number
          profession_id?: string | null
          target_countries?: string[]
          target_currency?: string | null
          target_pay_amount?: number | null
          target_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "career_goals_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "career_goals_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "career_goals_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      companies: {
        Row: {
          about: string | null
          company_kind: string
          country_code: string | null
          cover_url: string | null
          created_at: string
          created_by: string | null
          culture: Json
          deleted_at: string | null
          display_name: string
          founded_year: number | null
          hq_location_id: string | null
          id: string
          industry_id: string | null
          is_independent_recruiter: boolean
          is_verified: boolean
          legal_name: string | null
          logo_url: string | null
          media: Json
          median_response_hours: number | null
          registration_number: string | null
          response_rate_pct: number | null
          size_band: Database["public"]["Enums"]["company_size_band"] | null
          slug: string
          stats_computed_at: string | null
          tax_id: string | null
          total_hires: number
          updated_at: string
          verification_method:
            | Database["public"]["Enums"]["verification_method"]
            | null
          verified_at: string | null
          website: string | null
        }
        Insert: {
          about?: string | null
          company_kind?: string
          country_code?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          culture?: Json
          deleted_at?: string | null
          display_name: string
          founded_year?: number | null
          hq_location_id?: string | null
          id?: string
          industry_id?: string | null
          is_independent_recruiter?: boolean
          is_verified?: boolean
          legal_name?: string | null
          logo_url?: string | null
          media?: Json
          median_response_hours?: number | null
          registration_number?: string | null
          response_rate_pct?: number | null
          size_band?: Database["public"]["Enums"]["company_size_band"] | null
          slug: string
          stats_computed_at?: string | null
          tax_id?: string | null
          total_hires?: number
          updated_at?: string
          verification_method?:
            | Database["public"]["Enums"]["verification_method"]
            | null
          verified_at?: string | null
          website?: string | null
        }
        Update: {
          about?: string | null
          company_kind?: string
          country_code?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          culture?: Json
          deleted_at?: string | null
          display_name?: string
          founded_year?: number | null
          hq_location_id?: string | null
          id?: string
          industry_id?: string | null
          is_independent_recruiter?: boolean
          is_verified?: boolean
          legal_name?: string | null
          logo_url?: string | null
          media?: Json
          median_response_hours?: number | null
          registration_number?: string | null
          response_rate_pct?: number | null
          size_band?: Database["public"]["Enums"]["company_size_band"] | null
          slug?: string
          stats_computed_at?: string | null
          tax_id?: string | null
          total_hires?: number
          updated_at?: string
          verification_method?:
            | Database["public"]["Enums"]["verification_method"]
            | null
          verified_at?: string | null
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "companies_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "companies_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "companies_hq_location_id_fkey"
            columns: ["hq_location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "companies_industry_id_fkey"
            columns: ["industry_id"]
            isOneToOne: false
            referencedRelation: "industries"
            referencedColumns: ["id"]
          },
        ]
      }
      company_entitlements: {
        Row: {
          active_job_slots: number
          ai_credits_monthly: number
          company_id: string
          outreach_quota_daily: number
          plan: string
          recruiter_seats: number
          talent_search_enabled: boolean
          talent_search_quota_monthly: number
          updated_at: string
          valid_until: string | null
        }
        Insert: {
          active_job_slots?: number
          ai_credits_monthly?: number
          company_id: string
          outreach_quota_daily?: number
          plan?: string
          recruiter_seats?: number
          talent_search_enabled?: boolean
          talent_search_quota_monthly?: number
          updated_at?: string
          valid_until?: string | null
        }
        Update: {
          active_job_slots?: number
          ai_credits_monthly?: number
          company_id?: string
          outreach_quota_daily?: number
          plan?: string
          recruiter_seats?: number
          talent_search_enabled?: boolean
          talent_search_quota_monthly?: number
          updated_at?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_entitlements_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      company_invitations: {
        Row: {
          accepted_at: string | null
          company_id: string
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string | null
          role: Database["public"]["Enums"]["company_role"]
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          company_id: string
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by?: string | null
          role: Database["public"]["Enums"]["company_role"]
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          company_id?: string
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          role?: Database["public"]["Enums"]["company_role"]
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_invitations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      company_legal_entities: {
        Row: {
          company_id: string
          country_code: string
          created_at: string
          currency: string
          hiring_notes: string | null
          id: string
          is_default: boolean
          legal_name: string
          registration_number: string | null
          timezone: string
        }
        Insert: {
          company_id: string
          country_code: string
          created_at?: string
          currency: string
          hiring_notes?: string | null
          id?: string
          is_default?: boolean
          legal_name: string
          registration_number?: string | null
          timezone: string
        }
        Update: {
          company_id?: string
          country_code?: string
          created_at?: string
          currency?: string
          hiring_notes?: string | null
          id?: string
          is_default?: boolean
          legal_name?: string
          registration_number?: string | null
          timezone?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_legal_entities_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_legal_entities_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "company_legal_entities_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
        ]
      }
      company_locations: {
        Row: {
          address: string | null
          company_id: string
          created_at: string
          geo: unknown
          id: string
          is_hq: boolean
          legal_entity_id: string | null
          location_id: string | null
          name: string | null
        }
        Insert: {
          address?: string | null
          company_id: string
          created_at?: string
          geo?: unknown
          id?: string
          is_hq?: boolean
          legal_entity_id?: string | null
          location_id?: string | null
          name?: string | null
        }
        Update: {
          address?: string | null
          company_id?: string
          created_at?: string
          geo?: unknown
          id?: string
          is_hq?: boolean
          legal_entity_id?: string | null
          location_id?: string | null
          name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_locations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_locations_legal_entity_id_fkey"
            columns: ["legal_entity_id"]
            isOneToOne: false
            referencedRelation: "company_legal_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_locations_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      company_members: {
        Row: {
          company_id: string
          department_id: string | null
          id: string
          invited_by: string | null
          is_active: boolean
          joined_at: string
          person_id: string
          role: Database["public"]["Enums"]["company_role"]
          title: string | null
        }
        Insert: {
          company_id: string
          department_id?: string | null
          id?: string
          invited_by?: string | null
          is_active?: boolean
          joined_at?: string
          person_id: string
          role: Database["public"]["Enums"]["company_role"]
          title?: string | null
        }
        Update: {
          company_id?: string
          department_id?: string | null
          id?: string
          invited_by?: string | null
          is_active?: boolean
          joined_at?: string
          person_id?: string
          role?: Database["public"]["Enums"]["company_role"]
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_members_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_members_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_members_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_members_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          application_id: string | null
          company_archived: boolean
          company_id: string
          created_at: string
          id: string
          initiated_by: Database["public"]["Enums"]["actor_type"]
          job_id: string | null
          last_message_at: string | null
          person_archived: boolean
          person_id: string
          subject: string | null
        }
        Insert: {
          application_id?: string | null
          company_archived?: boolean
          company_id: string
          created_at?: string
          id?: string
          initiated_by?: Database["public"]["Enums"]["actor_type"]
          job_id?: string | null
          last_message_at?: string | null
          person_archived?: boolean
          person_id: string
          subject?: string | null
        }
        Update: {
          application_id?: string | null
          company_archived?: boolean
          company_id?: string
          created_at?: string
          id?: string
          initiated_by?: Database["public"]["Enums"]["actor_type"]
          job_id?: string | null
          last_message_at?: string | null
          person_archived?: boolean
          person_id?: string
          subject?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "conversations_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      country_employment_info: {
        Row: {
          country_code: string
          id: string
          official_url: string
          reviewed_at: string
          source_name: string
          summary: string
          title: string
          topic: string
        }
        Insert: {
          country_code: string
          id?: string
          official_url: string
          reviewed_at: string
          source_name: string
          summary: string
          title: string
          topic: string
        }
        Update: {
          country_code?: string
          id?: string
          official_url?: string
          reviewed_at?: string
          source_name?: string
          summary?: string
          title?: string
          topic?: string
        }
        Relationships: [
          {
            foreignKeyName: "country_employment_info_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
        ]
      }
      country_policies: {
        Row: {
          age_criteria_permitted: boolean
          calling_code: string | null
          country_code: string
          created_at: string
          default_currency: string
          default_language: string | null
          default_pay_period: Database["public"]["Enums"]["pay_period"]
          default_timezone: string | null
          gender_criteria_permitted: boolean
          legal_basis_note: string | null
          name: string
          phone_auth_preferred: boolean
          required_documents: Database["public"]["Enums"]["document_type"][]
          salary_disclosure_required: boolean
          supported: boolean
          world_region: string | null
        }
        Insert: {
          age_criteria_permitted?: boolean
          calling_code?: string | null
          country_code: string
          created_at?: string
          default_currency: string
          default_language?: string | null
          default_pay_period?: Database["public"]["Enums"]["pay_period"]
          default_timezone?: string | null
          gender_criteria_permitted?: boolean
          legal_basis_note?: string | null
          name: string
          phone_auth_preferred?: boolean
          required_documents?: Database["public"]["Enums"]["document_type"][]
          salary_disclosure_required?: boolean
          supported?: boolean
          world_region?: string | null
        }
        Update: {
          age_criteria_permitted?: boolean
          calling_code?: string | null
          country_code?: string
          created_at?: string
          default_currency?: string
          default_language?: string | null
          default_pay_period?: Database["public"]["Enums"]["pay_period"]
          default_timezone?: string | null
          gender_criteria_permitted?: boolean
          legal_basis_note?: string | null
          name?: string
          phone_auth_preferred?: boolean
          required_documents?: Database["public"]["Enums"]["document_type"][]
          salary_disclosure_required?: boolean
          supported?: boolean
          world_region?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "country_policies_default_currency_currency_fk"
            columns: ["default_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
        ]
      }
      credential_types: {
        Row: {
          category_id: string | null
          id: string
          issuer: string
          name: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl: string | null
        }
        Insert: {
          category_id?: string | null
          id?: string
          issuer: string
          name: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Update: {
          category_id?: string | null
          id?: string
          issuer?: string
          name?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "credential_types_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      currencies: {
        Row: {
          active: boolean
          code: string
          minor_units: number
          name: string
          symbol: string
        }
        Insert: {
          active?: boolean
          code: string
          minor_units?: number
          name: string
          symbol: string
        }
        Update: {
          active?: boolean
          code?: string
          minor_units?: number
          name?: string
          symbol?: string
        }
        Relationships: []
      }
      departments: {
        Row: {
          company_id: string
          created_at: string
          id: string
          name: string
          parent_id: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          name: string
          parent_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          name?: string
          parent_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "departments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "departments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      document_shares: {
        Row: {
          application_id: string | null
          company_id: string | null
          document_id: string
          expires_at: string | null
          granted_at: string
          id: string
          person_id: string
          revoked_at: string | null
        }
        Insert: {
          application_id?: string | null
          company_id?: string | null
          document_id: string
          expires_at?: string | null
          granted_at?: string
          id?: string
          person_id: string
          revoked_at?: string | null
        }
        Update: {
          application_id?: string | null
          company_id?: string | null
          document_id?: string
          expires_at?: string | null
          granted_at?: string
          id?: string
          person_id?: string
          revoked_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "document_shares_company_fk"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_shares_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_shares_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      documents: {
        Row: {
          created_at: string
          deleted_at: string | null
          expires_on: string | null
          id: string
          is_generated: boolean
          is_sensitive: boolean
          mime_type: string | null
          name: string
          person_id: string
          scan_status: string
          size_bytes: number | null
          storage_path: string
          type: Database["public"]["Enums"]["document_type"]
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          expires_on?: string | null
          id?: string
          is_generated?: boolean
          is_sensitive?: boolean
          mime_type?: string | null
          name: string
          person_id: string
          scan_status?: string
          size_bytes?: number | null
          storage_path: string
          type: Database["public"]["Enums"]["document_type"]
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          expires_on?: string | null
          id?: string
          is_generated?: boolean
          is_sensitive?: boolean
          mime_type?: string | null
          name?: string
          person_id?: string
          scan_status?: string
          size_bytes?: number | null
          storage_path?: string
          type?: Database["public"]["Enums"]["document_type"]
        }
        Relationships: [
          {
            foreignKeyName: "documents_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      domain_events: {
        Row: {
          actor_id: string | null
          aggregate_id: string
          aggregate_type: string
          company_id: string | null
          event_type: string
          id: number
          occurred_at: string
          payload: Json
          person_id: string | null
          processed_at: string | null
        }
        Insert: {
          actor_id?: string | null
          aggregate_id: string
          aggregate_type: string
          company_id?: string | null
          event_type: string
          id?: never
          occurred_at?: string
          payload?: Json
          person_id?: string | null
          processed_at?: string | null
        }
        Update: {
          actor_id?: string | null
          aggregate_id?: string
          aggregate_type?: string
          company_id?: string | null
          event_type?: string
          id?: never
          occurred_at?: string
          payload?: Json
          person_id?: string | null
          processed_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "domain_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "domain_events_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      earning_lines: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          description: string
          earning_id: string
          id: string
          kind: string
          quantity: number | null
          rate: number | null
          reason: string | null
          unit: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          description: string
          earning_id: string
          id?: string
          kind: string
          quantity?: number | null
          rate?: number | null
          reason?: string | null
          unit?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          description?: string
          earning_id?: string
          id?: string
          kind?: string
          quantity?: number | null
          rate?: number | null
          reason?: string | null
          unit?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "earning_lines_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_lines_earning_id_fkey"
            columns: ["earning_id"]
            isOneToOne: false
            referencedRelation: "earnings"
            referencedColumns: ["id"]
          },
        ]
      }
      earnings: {
        Row: {
          adjustment_amount: number
          allowance_amount: number
          approved_at: string | null
          approved_by: string | null
          assignment_id: string
          base_amount: number
          bonus_amount: number
          company_id: string
          created_at: string
          currency: string
          deduction_amount: number
          gross_amount: number | null
          id: string
          overtime_amount: number
          period_end: string
          period_start: string
          person_id: string
          status: string
          timesheet_id: string
          updated_at: string
        }
        Insert: {
          adjustment_amount?: number
          allowance_amount?: number
          approved_at?: string | null
          approved_by?: string | null
          assignment_id: string
          base_amount?: number
          bonus_amount?: number
          company_id: string
          created_at?: string
          currency: string
          deduction_amount?: number
          gross_amount?: number | null
          id?: string
          overtime_amount?: number
          period_end: string
          period_start: string
          person_id: string
          status?: string
          timesheet_id: string
          updated_at?: string
        }
        Update: {
          adjustment_amount?: number
          allowance_amount?: number
          approved_at?: string | null
          approved_by?: string | null
          assignment_id?: string
          base_amount?: number
          bonus_amount?: number
          company_id?: string
          created_at?: string
          currency?: string
          deduction_amount?: number
          gross_amount?: number | null
          id?: string
          overtime_amount?: number
          period_end?: string
          period_start?: string
          person_id?: string
          status?: string
          timesheet_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "earnings_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earnings_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earnings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earnings_currency_currency_fk"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "earnings_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earnings_timesheet_id_fkey"
            columns: ["timesheet_id"]
            isOneToOne: true
            referencedRelation: "timesheets"
            referencedColumns: ["id"]
          },
        ]
      }
      educations: {
        Row: {
          created_at: string
          ended_on: string | null
          field_of_study: string | null
          grade: string | null
          id: string
          institution_id: string | null
          institution_name: string
          is_ongoing: boolean
          is_verified: boolean
          level: Database["public"]["Enums"]["education_level"]
          person_id: string
          source: Database["public"]["Enums"]["source_type"]
          started_on: string | null
        }
        Insert: {
          created_at?: string
          ended_on?: string | null
          field_of_study?: string | null
          grade?: string | null
          id?: string
          institution_id?: string | null
          institution_name: string
          is_ongoing?: boolean
          is_verified?: boolean
          level: Database["public"]["Enums"]["education_level"]
          person_id: string
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
        }
        Update: {
          created_at?: string
          ended_on?: string | null
          field_of_study?: string | null
          grade?: string | null
          id?: string
          institution_id?: string | null
          institution_name?: string
          is_ongoing?: boolean
          is_verified?: boolean
          level?: Database["public"]["Enums"]["education_level"]
          person_id?: string
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "educations_institution_id_fkey"
            columns: ["institution_id"]
            isOneToOne: false
            referencedRelation: "institutions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      employments: {
        Row: {
          application_id: string | null
          company_id: string
          country_code: string | null
          created_at: string
          department_id: string | null
          employment_type: string | null
          end_reason: string | null
          ended_on: string | null
          id: string
          is_omelo_hire: boolean
          job_id: string | null
          location_id: string | null
          offer_id: string | null
          pay_amount: number | null
          pay_currency: string | null
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          profession_id: string | null
          started_on: string
          status: Database["public"]["Enums"]["employment_status"]
          title: string
          updated_at: string
          work_type: Database["public"]["Enums"]["work_type"] | null
          workplace_type: Database["public"]["Enums"]["workplace_type"] | null
        }
        Insert: {
          application_id?: string | null
          company_id: string
          country_code?: string | null
          created_at?: string
          department_id?: string | null
          employment_type?: string | null
          end_reason?: string | null
          ended_on?: string | null
          id?: string
          is_omelo_hire?: boolean
          job_id?: string | null
          location_id?: string | null
          offer_id?: string | null
          pay_amount?: number | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          profession_id?: string | null
          started_on: string
          status?: Database["public"]["Enums"]["employment_status"]
          title: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Update: {
          application_id?: string | null
          company_id?: string
          country_code?: string | null
          created_at?: string
          department_id?: string | null
          employment_type?: string | null
          end_reason?: string | null
          ended_on?: string | null
          id?: string
          is_omelo_hire?: boolean
          job_id?: string | null
          location_id?: string | null
          offer_id?: string | null
          pay_amount?: number | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id?: string
          profession_id?: string | null
          started_on?: string
          status?: Database["public"]["Enums"]["employment_status"]
          title?: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "employments_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "employments_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_offer_id_fkey"
            columns: ["offer_id"]
            isOneToOne: false
            referencedRelation: "offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_pay_currency_fkey"
            columns: ["pay_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "employments_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employments_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      exchange_rates: {
        Row: {
          base: string
          created_at: string
          created_by: string | null
          effective_at: string
          id: number
          quote: string
          rate: number
          source: string
        }
        Insert: {
          base: string
          created_at?: string
          created_by?: string | null
          effective_at: string
          id?: never
          quote: string
          rate: number
          source: string
        }
        Update: {
          base?: string
          created_at?: string
          created_by?: string | null
          effective_at?: string
          id?: never
          quote?: string
          rate?: number
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "exchange_rates_base_fkey"
            columns: ["base"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "exchange_rates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "exchange_rates_quote_fkey"
            columns: ["quote"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
        ]
      }
      experiences: {
        Row: {
          company_id: string | null
          country_code: string | null
          created_at: string
          description: string | null
          employer_name: string
          ended_on: string | null
          id: string
          is_current: boolean
          is_informal: boolean
          is_self_employed: boolean
          is_verified: boolean
          location_id: string | null
          location_text: string | null
          months_duration: number | null
          pay_amount: number | null
          pay_currency: string | null
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          profession_id: string | null
          reason_for_leaving: string | null
          responsibilities: Json
          source: Database["public"]["Enums"]["source_type"]
          started_on: string | null
          title: string
          verified_employment_id: string | null
          work_identity_id: string | null
          work_type: Database["public"]["Enums"]["work_type"] | null
          workplace_type: Database["public"]["Enums"]["workplace_type"] | null
        }
        Insert: {
          company_id?: string | null
          country_code?: string | null
          created_at?: string
          description?: string | null
          employer_name: string
          ended_on?: string | null
          id?: string
          is_current?: boolean
          is_informal?: boolean
          is_self_employed?: boolean
          is_verified?: boolean
          location_id?: string | null
          location_text?: string | null
          months_duration?: number | null
          pay_amount?: number | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          profession_id?: string | null
          reason_for_leaving?: string | null
          responsibilities?: Json
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
          title: string
          verified_employment_id?: string | null
          work_identity_id?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Update: {
          company_id?: string | null
          country_code?: string | null
          created_at?: string
          description?: string | null
          employer_name?: string
          ended_on?: string | null
          id?: string
          is_current?: boolean
          is_informal?: boolean
          is_self_employed?: boolean
          is_verified?: boolean
          location_id?: string | null
          location_text?: string | null
          months_duration?: number | null
          pay_amount?: number | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id?: string
          profession_id?: string | null
          reason_for_leaving?: string | null
          responsibilities?: Json
          source?: Database["public"]["Enums"]["source_type"]
          started_on?: string | null
          title?: string
          verified_employment_id?: string | null
          work_identity_id?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "experiences_company_fk"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "experiences_employment_fk"
            columns: ["verified_employment_id"]
            isOneToOne: false
            referencedRelation: "employments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_pay_currency_currency_fk"
            columns: ["pay_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "experiences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "experiences_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      follows: {
        Row: {
          created_at: string
          person_id: string
          target_id: string
          target_type: string
        }
        Insert: {
          created_at?: string
          person_id: string
          target_id: string
          target_type: string
        }
        Update: {
          created_at?: string
          person_id?: string
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "follows_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      fraud_signals: {
        Row: {
          detail: Json
          detected_at: string
          id: number
          severity: number
          signal: string
          subject_id: string
          subject_type: string
        }
        Insert: {
          detail?: Json
          detected_at?: string
          id?: number
          severity?: number
          signal: string
          subject_id: string
          subject_type: string
        }
        Update: {
          detail?: Json
          detected_at?: string
          id?: number
          severity?: number
          signal?: string
          subject_id?: string
          subject_type?: string
        }
        Relationships: []
      }
      hidden_jobs: {
        Row: {
          created_at: string
          job_id: string
          person_id: string
          reason: string | null
        }
        Insert: {
          created_at?: string
          job_id: string
          person_id: string
          reason?: string | null
        }
        Update: {
          created_at?: string
          job_id?: string
          person_id?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hidden_jobs_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hidden_jobs_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      industries: {
        Row: {
          id: string
          name: string
          parent_id: string | null
          slug: string
        }
        Insert: {
          id?: string
          name: string
          parent_id?: string | null
          slug: string
        }
        Update: {
          id?: string
          name?: string
          parent_id?: string | null
          slug?: string
        }
        Relationships: [
          {
            foreignKeyName: "industries_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "industries"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_runs: {
        Row: {
          errors: Json
          finished_at: string | null
          id: string
          jobs_closed: number
          jobs_created: number
          jobs_seen: number
          jobs_updated: number
          source_id: string
          started_at: string
        }
        Insert: {
          errors?: Json
          finished_at?: string | null
          id?: string
          jobs_closed?: number
          jobs_created?: number
          jobs_seen?: number
          jobs_updated?: number
          source_id: string
          started_at?: string
        }
        Update: {
          errors?: Json
          finished_at?: string | null
          id?: string
          jobs_closed?: number
          jobs_created?: number
          jobs_seen?: number
          jobs_updated?: number
          source_id?: string
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_runs_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "job_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      institutions: {
        Row: {
          country_code: string | null
          created_at: string
          id: string
          name: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          website: string | null
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          id?: string
          name: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          website?: string | null
        }
        Update: {
          country_code?: string | null
          created_at?: string
          id?: string
          name?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          website?: string | null
        }
        Relationships: []
      }
      interview_answers: {
        Row: {
          created_at: string
          evaluation: string | null
          id: string
          interview_id: string
          interviewer_id: string
          notes: string | null
          question_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          evaluation?: string | null
          id?: string
          interview_id: string
          interviewer_id: string
          notes?: string | null
          question_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          evaluation?: string | null
          id?: string
          interview_id?: string
          interviewer_id?: string
          notes?: string | null
          question_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_answers_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_answers_interviewer_id_fkey"
            columns: ["interviewer_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_answers_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "interview_questions"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_feedback: {
        Row: {
          application_id: string
          company_id: string
          competencies: Json
          concerns: string | null
          created_at: string
          id: string
          interview_id: string
          interviewer_id: string
          notes: string | null
          overall_rating: number | null
          recommendation: string | null
          skills_assessed: Json
          status: string
          strengths: string | null
          submitted_at: string | null
          updated_at: string
        }
        Insert: {
          application_id: string
          company_id: string
          competencies?: Json
          concerns?: string | null
          created_at?: string
          id?: string
          interview_id: string
          interviewer_id: string
          notes?: string | null
          overall_rating?: number | null
          recommendation?: string | null
          skills_assessed?: Json
          status?: string
          strengths?: string | null
          submitted_at?: string | null
          updated_at?: string
        }
        Update: {
          application_id?: string
          company_id?: string
          competencies?: Json
          concerns?: string | null
          created_at?: string
          id?: string
          interview_id?: string
          interviewer_id?: string
          notes?: string | null
          overall_rating?: number | null
          recommendation?: string | null
          skills_assessed?: Json
          status?: string
          strengths?: string | null
          submitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_feedback_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_feedback_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_feedback_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_feedback_interviewer_id_fkey"
            columns: ["interviewer_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_interviewers: {
        Row: {
          interview_id: string
          is_lead: boolean
          person_id: string
        }
        Insert: {
          interview_id: string
          is_lead?: boolean
          person_id: string
        }
        Update: {
          interview_id?: string
          is_lead?: boolean
          person_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_interviewers_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_interviewers_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_participants: {
        Row: {
          admitted_at: string | null
          admitted_by: string | null
          display_name: string | null
          id: string
          interview_id: string
          invited_at: string
          joined_at: string | null
          left_at: string | null
          person_id: string
          remove_reason: string | null
          removed_at: string | null
          removed_by: string | null
          requested_at: string | null
          role: string
          status: string
        }
        Insert: {
          admitted_at?: string | null
          admitted_by?: string | null
          display_name?: string | null
          id?: string
          interview_id: string
          invited_at?: string
          joined_at?: string | null
          left_at?: string | null
          person_id: string
          remove_reason?: string | null
          removed_at?: string | null
          removed_by?: string | null
          requested_at?: string | null
          role: string
          status?: string
        }
        Update: {
          admitted_at?: string | null
          admitted_by?: string | null
          display_name?: string | null
          id?: string
          interview_id?: string
          invited_at?: string
          joined_at?: string | null
          left_at?: string | null
          person_id?: string
          remove_reason?: string | null
          removed_at?: string | null
          removed_by?: string | null
          requested_at?: string | null
          role?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_participants_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_participants_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_question_templates: {
        Row: {
          category: string
          category_id: string | null
          created_at: string
          id: string
          is_active: boolean
          locale: string
          position: number
          profession_id: string | null
          question: string
          round_kind: string | null
        }
        Insert: {
          category?: string
          category_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          locale?: string
          position?: number
          profession_id?: string | null
          question: string
          round_kind?: string | null
        }
        Update: {
          category?: string
          category_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          locale?: string
          position?: number
          profession_id?: string | null
          question?: string
          round_kind?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "interview_question_templates_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_question_templates_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_questions: {
        Row: {
          category: string
          created_at: string
          id: string
          interview_id: string
          position: number
          question: string
          required: boolean
          source: string
          template_id: string | null
        }
        Insert: {
          category?: string
          created_at?: string
          id?: string
          interview_id: string
          position?: number
          question: string
          required?: boolean
          source?: string
          template_id?: string | null
        }
        Update: {
          category?: string
          created_at?: string
          id?: string
          interview_id?: string
          position?: number
          question?: string
          required?: boolean
          source?: string
          template_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "interview_questions_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_questions_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "interview_question_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_rooms: {
        Row: {
          closes_at: string
          created_at: string
          ended_at: string | null
          ended_by: string | null
          id: string
          interview_id: string
          opens_at: string
          recording_enabled: boolean
          room_name: string
          started_at: string | null
          status: string
          waiting_room: boolean
        }
        Insert: {
          closes_at: string
          created_at?: string
          ended_at?: string | null
          ended_by?: string | null
          id?: string
          interview_id: string
          opens_at: string
          recording_enabled?: boolean
          room_name?: string
          started_at?: string | null
          status?: string
          waiting_room?: boolean
        }
        Update: {
          closes_at?: string
          created_at?: string
          ended_at?: string | null
          ended_by?: string | null
          id?: string
          interview_id?: string
          opens_at?: string
          recording_enabled?: boolean
          room_name?: string
          started_at?: string | null
          status?: string
          waiting_room?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "interview_rooms_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: true
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_scorecards: {
        Row: {
          id: string
          interview_id: string
          interviewer_id: string
          notes: string | null
          overall_score: number | null
          recommendation:
            | Database["public"]["Enums"]["interview_recommendation"]
            | null
          scores: Json
          submitted_at: string
        }
        Insert: {
          id?: string
          interview_id: string
          interviewer_id: string
          notes?: string | null
          overall_score?: number | null
          recommendation?:
            | Database["public"]["Enums"]["interview_recommendation"]
            | null
          scores?: Json
          submitted_at?: string
        }
        Update: {
          id?: string
          interview_id?: string
          interviewer_id?: string
          notes?: string | null
          overall_score?: number | null
          recommendation?:
            | Database["public"]["Enums"]["interview_recommendation"]
            | null
          scores?: Json
          submitted_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_scorecards_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_scorecards_interviewer_id_fkey"
            columns: ["interviewer_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      interview_sessions: {
        Row: {
          duration_seconds: number | null
          ended_at: string | null
          id: string
          interview_id: string
          room_id: string
          started_at: string
        }
        Insert: {
          duration_seconds?: number | null
          ended_at?: string | null
          id?: string
          interview_id: string
          room_id: string
          started_at?: string
        }
        Update: {
          duration_seconds?: number | null
          ended_at?: string | null
          id?: string
          interview_id?: string
          room_id?: string
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "interview_sessions_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interview_sessions_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "interview_rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      interviews: {
        Row: {
          application_id: string
          cancel_reason: string | null
          cancelled_at: string | null
          candidate_confirmed_at: string | null
          company_id: string
          completed_at: string | null
          created_at: string
          created_by: string | null
          duration_minutes: number | null
          geo: unknown
          id: string
          instructions: string | null
          job_id: string
          location_text: string | null
          meeting_mode: string
          meeting_url: string | null
          person_id: string
          round: number
          round_kind: string | null
          round_name: string | null
          scheduled_at: string | null
          status: Database["public"]["Enums"]["interview_status"]
          timezone: string | null
          type: Database["public"]["Enums"]["interview_type"]
        }
        Insert: {
          application_id: string
          cancel_reason?: string | null
          cancelled_at?: string | null
          candidate_confirmed_at?: string | null
          company_id: string
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          duration_minutes?: number | null
          geo?: unknown
          id?: string
          instructions?: string | null
          job_id: string
          location_text?: string | null
          meeting_mode?: string
          meeting_url?: string | null
          person_id: string
          round?: number
          round_kind?: string | null
          round_name?: string | null
          scheduled_at?: string | null
          status?: Database["public"]["Enums"]["interview_status"]
          timezone?: string | null
          type: Database["public"]["Enums"]["interview_type"]
        }
        Update: {
          application_id?: string
          cancel_reason?: string | null
          cancelled_at?: string | null
          candidate_confirmed_at?: string | null
          company_id?: string
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          duration_minutes?: number | null
          geo?: unknown
          id?: string
          instructions?: string | null
          job_id?: string
          location_text?: string | null
          meeting_mode?: string
          meeting_url?: string | null
          person_id?: string
          round?: number
          round_kind?: string | null
          round_name?: string | null
          scheduled_at?: string | null
          status?: Database["public"]["Enums"]["interview_status"]
          timezone?: string | null
          type?: Database["public"]["Enums"]["interview_type"]
        }
        Relationships: [
          {
            foreignKeyName: "interviews_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "interviews_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      job_attribute_requirements: {
        Row: {
          attribute_id: string
          job_id: string
          requirement_level: Database["public"]["Enums"]["requirement_level"]
          value_bool: boolean | null
          value_json: Json | null
          value_number_max: number | null
          value_number_min: number | null
          value_text: string | null
        }
        Insert: {
          attribute_id: string
          job_id: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          value_bool?: boolean | null
          value_json?: Json | null
          value_number_max?: number | null
          value_number_min?: number | null
          value_text?: string | null
        }
        Update: {
          attribute_id?: string
          job_id?: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          value_bool?: boolean | null
          value_json?: Json | null
          value_number_max?: number | null
          value_number_min?: number | null
          value_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "job_attribute_requirements_attribute_id_fkey"
            columns: ["attribute_id"]
            isOneToOne: false
            referencedRelation: "profile_attributes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_attribute_requirements_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_benefits: {
        Row: {
          benefit_type: Database["public"]["Enums"]["benefit_type"]
          detail: string | null
          job_id: string
        }
        Insert: {
          benefit_type: Database["public"]["Enums"]["benefit_type"]
          detail?: string | null
          job_id: string
        }
        Update: {
          benefit_type?: Database["public"]["Enums"]["benefit_type"]
          detail?: string | null
          job_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_benefits_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_categories: {
        Row: {
          created_at: string
          icon: string | null
          id: string
          name: string
          position: number
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
        }
        Insert: {
          created_at?: string
          icon?: string | null
          id?: string
          name: string
          position?: number
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Update: {
          created_at?: string
          icon?: string | null
          id?: string
          name?: string
          position?: number
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Relationships: []
      }
      job_credentials: {
        Row: {
          credential_type_id: string
          job_id: string
          requirement_level: Database["public"]["Enums"]["requirement_level"]
        }
        Insert: {
          credential_type_id: string
          job_id: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Update: {
          credential_type_id?: string
          job_id?: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Relationships: [
          {
            foreignKeyName: "job_credentials_credential_type_id_fkey"
            columns: ["credential_type_id"]
            isOneToOne: false
            referencedRelation: "credential_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_credentials_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_documents_required: {
        Row: {
          document_type: Database["public"]["Enums"]["document_type"]
          is_required: boolean
          job_id: string
          request_at_stage: string
        }
        Insert: {
          document_type: Database["public"]["Enums"]["document_type"]
          is_required?: boolean
          job_id: string
          request_at_stage?: string
        }
        Update: {
          document_type?: Database["public"]["Enums"]["document_type"]
          is_required?: boolean
          job_id?: string
          request_at_stage?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_documents_required_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_interview_rounds: {
        Row: {
          created_at: string
          duration_minutes: number
          id: string
          job_id: string
          kind: string
          meeting_mode: string
          name: string
          position: number
        }
        Insert: {
          created_at?: string
          duration_minutes?: number
          id?: string
          job_id: string
          kind?: string
          meeting_mode?: string
          name: string
          position: number
        }
        Update: {
          created_at?: string
          duration_minutes?: number
          id?: string
          job_id?: string
          kind?: string
          meeting_mode?: string
          name?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "job_interview_rounds_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_languages: {
        Row: {
          job_id: string
          language_code: string
          min_proficiency: Database["public"]["Enums"]["language_proficiency"]
          requirement_level: Database["public"]["Enums"]["requirement_level"]
        }
        Insert: {
          job_id: string
          language_code: string
          min_proficiency?: Database["public"]["Enums"]["language_proficiency"]
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Update: {
          job_id?: string
          language_code?: string
          min_proficiency?: Database["public"]["Enums"]["language_proficiency"]
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Relationships: [
          {
            foreignKeyName: "job_languages_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_languages_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
        ]
      }
      job_legal_restrictions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          gender_requirement: string | null
          job_id: string
          legal_basis: string
          max_age: number | null
          min_age: number | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          gender_requirement?: string | null
          job_id: string
          legal_basis: string
          max_age?: number | null
          min_age?: number | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          gender_requirement?: string | null
          job_id?: string
          legal_basis?: string
          max_age?: number | null
          min_age?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "job_legal_restrictions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_legal_restrictions_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: true
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_licenses: {
        Row: {
          job_id: string
          license_class: string | null
          license_type_id: string
          requirement_level: Database["public"]["Enums"]["requirement_level"]
        }
        Insert: {
          job_id: string
          license_class?: string | null
          license_type_id: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Update: {
          job_id?: string
          license_class?: string | null
          license_type_id?: string
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
        }
        Relationships: [
          {
            foreignKeyName: "job_licenses_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_licenses_license_type_id_fkey"
            columns: ["license_type_id"]
            isOneToOne: false
            referencedRelation: "license_types"
            referencedColumns: ["id"]
          },
        ]
      }
      job_locations: {
        Row: {
          job_id: string
          location_id: string
        }
        Insert: {
          job_id: string
          location_id: string
        }
        Update: {
          job_id?: string
          location_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_locations_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_locations_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      job_order_recruiters: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          job_order_id: string
          person_id: string
          role: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          job_order_id: string
          person_id: string
          role?: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          job_order_id?: string
          person_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_order_recruiters_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_order_recruiters_job_order_id_fkey"
            columns: ["job_order_id"]
            isOneToOne: false
            referencedRelation: "job_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_order_recruiters_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      job_orders: {
        Row: {
          agency_id: string
          client_id: string
          client_job_id: string | null
          closing_date: string | null
          created_at: string
          created_by: string | null
          description: string | null
          hard_requirements: string[]
          id: string
          job_id: string
          location_id: string | null
          location_text: string | null
          min_experience_months: number | null
          notes: string | null
          openings: number
          pay_currency: string | null
          pay_max: number | null
          pay_min: number | null
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          priority: string
          profession_id: string | null
          reference: string
          required_skill_ids: string[]
          shift_types: Database["public"]["Enums"]["shift_type"][]
          start_date: string | null
          status: string
          title: string
          updated_at: string
          work_type: Database["public"]["Enums"]["work_type"]
          workplace_type: Database["public"]["Enums"]["workplace_type"]
        }
        Insert: {
          agency_id: string
          client_id: string
          client_job_id?: string | null
          closing_date?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          hard_requirements?: string[]
          id?: string
          job_id: string
          location_id?: string | null
          location_text?: string | null
          min_experience_months?: number | null
          notes?: string | null
          openings?: number
          pay_currency?: string | null
          pay_max?: number | null
          pay_min?: number | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          priority?: string
          profession_id?: string | null
          reference: string
          required_skill_ids?: string[]
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          start_date?: string | null
          status?: string
          title: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"]
          workplace_type?: Database["public"]["Enums"]["workplace_type"]
        }
        Update: {
          agency_id?: string
          client_id?: string
          client_job_id?: string | null
          closing_date?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          hard_requirements?: string[]
          id?: string
          job_id?: string
          location_id?: string | null
          location_text?: string | null
          min_experience_months?: number | null
          notes?: string | null
          openings?: number
          pay_currency?: string | null
          pay_max?: number | null
          pay_min?: number | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          priority?: string
          profession_id?: string | null
          reference?: string
          required_skill_ids?: string[]
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          start_date?: string | null
          status?: string
          title?: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"]
          workplace_type?: Database["public"]["Enums"]["workplace_type"]
        }
        Relationships: [
          {
            foreignKeyName: "job_orders_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_orders_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_orders_client_job_id_fkey"
            columns: ["client_job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_orders_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_orders_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: true
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_orders_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_orders_pay_currency_currency_fk"
            columns: ["pay_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "job_orders_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      job_questions: {
        Row: {
          answer_type: string
          id: string
          is_knockout: boolean
          is_required: boolean
          job_id: string
          knockout_expected: Json | null
          options: Json | null
          position: number
          prompt: string
        }
        Insert: {
          answer_type: string
          id?: string
          is_knockout?: boolean
          is_required?: boolean
          job_id: string
          knockout_expected?: Json | null
          options?: Json | null
          position: number
          prompt: string
        }
        Update: {
          answer_type?: string
          id?: string
          is_knockout?: boolean
          is_required?: boolean
          job_id?: string
          knockout_expected?: Json | null
          options?: Json | null
          position?: number
          prompt?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_questions_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_skills: {
        Row: {
          job_id: string
          min_months: number | null
          requirement_level: Database["public"]["Enums"]["requirement_level"]
          skill_id: string
          weight: number
        }
        Insert: {
          job_id: string
          min_months?: number | null
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          skill_id: string
          weight?: number
        }
        Update: {
          job_id?: string
          min_months?: number | null
          requirement_level?: Database["public"]["Enums"]["requirement_level"]
          skill_id?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "job_skills_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      job_sources: {
        Row: {
          contract_ref: string | null
          created_at: string
          id: string
          is_active: boolean
          kind: string
          last_synced_at: string | null
          name: string
          terms_url: string | null
        }
        Insert: {
          contract_ref?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          kind: string
          last_synced_at?: string | null
          name: string
          terms_url?: string | null
        }
        Update: {
          contract_ref?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          kind?: string
          last_synced_at?: string | null
          name?: string
          terms_url?: string | null
        }
        Relationships: []
      }
      job_stages: {
        Row: {
          created_at: string
          id: string
          is_terminal: boolean
          job_id: string
          maps_to_state: Database["public"]["Enums"]["application_state"]
          name: string
          position: number
        }
        Insert: {
          created_at?: string
          id?: string
          is_terminal?: boolean
          job_id: string
          maps_to_state: Database["public"]["Enums"]["application_state"]
          name: string
          position: number
        }
        Update: {
          created_at?: string
          id?: string
          is_terminal?: boolean
          job_id?: string
          maps_to_state?: Database["public"]["Enums"]["application_state"]
          name?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "job_stages_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      jobs: {
        Row: {
          accepts_no_experience: boolean
          accepts_non_residents: boolean | null
          accommodation_assistance: boolean
          applicant_count: number
          application_method: string
          category_id: string | null
          closed_at: string | null
          company_id: string
          company_location_id: string | null
          contact_phone: string | null
          content_language: string | null
          country_code: string | null
          created_at: string
          created_by: string | null
          department_id: string | null
          description: string | null
          duration_months: number | null
          education_negotiable: boolean
          expires_at: string | null
          external_apply_url: string | null
          external_id: string | null
          external_source_id: string | null
          geo: unknown
          hours_per_week: number | null
          id: string
          immigration_support: boolean
          is_immediate_start: boolean
          job_embedding: string | null
          legal_entity_id: string | null
          legal_support: boolean
          location_id: string | null
          location_text: string | null
          max_experience_months: number | null
          min_education: Database["public"]["Enums"]["education_level"] | null
          min_experience_months: number | null
          openings: number
          overtime_available: boolean | null
          own_tools_required: boolean | null
          own_vehicle_required: boolean | null
          pay_basis: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency: string | null
          pay_disclosed: boolean | null
          pay_max: number | null
          pay_min: number | null
          pay_negotiable: boolean
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          physical_requirements: Json
          profession_id: string | null
          profession_source: Database["public"]["Enums"]["source_type"] | null
          published_at: string | null
          quick_apply_enabled: boolean
          relocation_support: boolean
          remote_countries: string[]
          remote_scope: string | null
          remote_tz_max_offset: number | null
          remote_tz_min_offset: number | null
          requirements_text: Json
          requires_resume: boolean
          responsibilities: Json
          schedule_note: string | null
          shift_types: Database["public"]["Enums"]["shift_type"][]
          source: Database["public"]["Enums"]["source_type"]
          sponsorship: string
          sponsorship_type: string | null
          start_date: string | null
          status: Database["public"]["Enums"]["job_status"]
          title: string
          travel_assistance: boolean
          uniform_required: boolean | null
          updated_at: string
          view_count: number
          visa_fees_covered: boolean
          visa_sponsorship: boolean | null
          walk_in_details: string | null
          work_environment: string | null
          work_type: Database["public"]["Enums"]["work_type"]
          working_days: number | null
          workplace_type: Database["public"]["Enums"]["workplace_type"]
        }
        Insert: {
          accepts_no_experience?: boolean
          accepts_non_residents?: boolean | null
          accommodation_assistance?: boolean
          applicant_count?: number
          application_method?: string
          category_id?: string | null
          closed_at?: string | null
          company_id: string
          company_location_id?: string | null
          contact_phone?: string | null
          content_language?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          description?: string | null
          duration_months?: number | null
          education_negotiable?: boolean
          expires_at?: string | null
          external_apply_url?: string | null
          external_id?: string | null
          external_source_id?: string | null
          geo?: unknown
          hours_per_week?: number | null
          id?: string
          immigration_support?: boolean
          is_immediate_start?: boolean
          job_embedding?: string | null
          legal_entity_id?: string | null
          legal_support?: boolean
          location_id?: string | null
          location_text?: string | null
          max_experience_months?: number | null
          min_education?: Database["public"]["Enums"]["education_level"] | null
          min_experience_months?: number | null
          openings?: number
          overtime_available?: boolean | null
          own_tools_required?: boolean | null
          own_vehicle_required?: boolean | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_disclosed?: boolean | null
          pay_max?: number | null
          pay_min?: number | null
          pay_negotiable?: boolean
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          physical_requirements?: Json
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"] | null
          published_at?: string | null
          quick_apply_enabled?: boolean
          relocation_support?: boolean
          remote_countries?: string[]
          remote_scope?: string | null
          remote_tz_max_offset?: number | null
          remote_tz_min_offset?: number | null
          requirements_text?: Json
          requires_resume?: boolean
          responsibilities?: Json
          schedule_note?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          source?: Database["public"]["Enums"]["source_type"]
          sponsorship?: string
          sponsorship_type?: string | null
          start_date?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          title: string
          travel_assistance?: boolean
          uniform_required?: boolean | null
          updated_at?: string
          view_count?: number
          visa_fees_covered?: boolean
          visa_sponsorship?: boolean | null
          walk_in_details?: string | null
          work_environment?: string | null
          work_type?: Database["public"]["Enums"]["work_type"]
          working_days?: number | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"]
        }
        Update: {
          accepts_no_experience?: boolean
          accepts_non_residents?: boolean | null
          accommodation_assistance?: boolean
          applicant_count?: number
          application_method?: string
          category_id?: string | null
          closed_at?: string | null
          company_id?: string
          company_location_id?: string | null
          contact_phone?: string | null
          content_language?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          description?: string | null
          duration_months?: number | null
          education_negotiable?: boolean
          expires_at?: string | null
          external_apply_url?: string | null
          external_id?: string | null
          external_source_id?: string | null
          geo?: unknown
          hours_per_week?: number | null
          id?: string
          immigration_support?: boolean
          is_immediate_start?: boolean
          job_embedding?: string | null
          legal_entity_id?: string | null
          legal_support?: boolean
          location_id?: string | null
          location_text?: string | null
          max_experience_months?: number | null
          min_education?: Database["public"]["Enums"]["education_level"] | null
          min_experience_months?: number | null
          openings?: number
          overtime_available?: boolean | null
          own_tools_required?: boolean | null
          own_vehicle_required?: boolean | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_disclosed?: boolean | null
          pay_max?: number | null
          pay_min?: number | null
          pay_negotiable?: boolean
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          physical_requirements?: Json
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"] | null
          published_at?: string | null
          quick_apply_enabled?: boolean
          relocation_support?: boolean
          remote_countries?: string[]
          remote_scope?: string | null
          remote_tz_max_offset?: number | null
          remote_tz_min_offset?: number | null
          requirements_text?: Json
          requires_resume?: boolean
          responsibilities?: Json
          schedule_note?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          source?: Database["public"]["Enums"]["source_type"]
          sponsorship?: string
          sponsorship_type?: string | null
          start_date?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          title?: string
          travel_assistance?: boolean
          uniform_required?: boolean | null
          updated_at?: string
          view_count?: number
          visa_fees_covered?: boolean
          visa_sponsorship?: boolean | null
          walk_in_details?: string | null
          work_environment?: string | null
          work_type?: Database["public"]["Enums"]["work_type"]
          working_days?: number | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"]
        }
        Relationships: [
          {
            foreignKeyName: "jobs_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_company_location_id_fkey"
            columns: ["company_location_id"]
            isOneToOne: false
            referencedRelation: "company_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "jobs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_external_source_fk"
            columns: ["external_source_id"]
            isOneToOne: false
            referencedRelation: "job_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_legal_entity_fk"
            columns: ["legal_entity_id"]
            isOneToOne: false
            referencedRelation: "company_legal_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_pay_currency_currency_fk"
            columns: ["pay_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "jobs_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      languages: {
        Row: {
          code: string
          name: string
          native_name: string | null
          rtl: boolean
        }
        Insert: {
          code: string
          name: string
          native_name?: string | null
          rtl?: boolean
        }
        Update: {
          code?: string
          name?: string
          native_name?: string | null
          rtl?: boolean
        }
        Relationships: []
      }
      leave_requests: {
        Row: {
          assignment_id: string
          company_id: string
          created_at: string
          end_date: string
          id: string
          label: string | null
          leave_type: string
          person_id: string
          reason: string | null
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          start_date: string
          status: string
          updated_at: string
        }
        Insert: {
          assignment_id: string
          company_id: string
          created_at?: string
          end_date: string
          id?: string
          label?: string | null
          leave_type: string
          person_id: string
          reason?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          start_date: string
          status?: string
          updated_at?: string
        }
        Update: {
          assignment_id?: string
          company_id?: string
          created_at?: string
          end_date?: string
          id?: string
          label?: string | null
          leave_type?: string
          person_id?: string
          reason?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          start_date?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_requests_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      license_requirements: {
        Row: {
          country_code: string
          credential_type_id: string | null
          description: string | null
          id: string
          license_type_id: string | null
          name: string
          official_url: string | null
          profession_id: string
          region_code: string | null
          requirement_level: string
          reviewed_at: string | null
          source: string
        }
        Insert: {
          country_code: string
          credential_type_id?: string | null
          description?: string | null
          id?: string
          license_type_id?: string | null
          name: string
          official_url?: string | null
          profession_id: string
          region_code?: string | null
          requirement_level?: string
          reviewed_at?: string | null
          source: string
        }
        Update: {
          country_code?: string
          credential_type_id?: string | null
          description?: string | null
          id?: string
          license_type_id?: string | null
          name?: string
          official_url?: string | null
          profession_id?: string
          region_code?: string | null
          requirement_level?: string
          reviewed_at?: string | null
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "license_requirements_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "license_requirements_credential_type_id_fkey"
            columns: ["credential_type_id"]
            isOneToOne: false
            referencedRelation: "credential_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "license_requirements_license_type_id_fkey"
            columns: ["license_type_id"]
            isOneToOne: false
            referencedRelation: "license_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "license_requirements_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      license_types: {
        Row: {
          category_id: string | null
          class_options: string[]
          country_code: string | null
          created_at: string
          id: string
          issuing_body: string | null
          name: string
          renewable: boolean
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl: string | null
        }
        Insert: {
          category_id?: string | null
          class_options?: string[]
          country_code?: string | null
          created_at?: string
          id?: string
          issuing_body?: string | null
          name: string
          renewable?: boolean
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Update: {
          category_id?: string | null
          class_options?: string[]
          country_code?: string | null
          created_at?: string
          id?: string
          issuing_body?: string | null
          name?: string
          renewable?: boolean
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          verify_url_tpl?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "license_types_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "license_types_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
        ]
      }
      locations: {
        Row: {
          admin_code: string | null
          country_code: string | null
          created_at: string
          currency_code: string | null
          geo: unknown
          id: string
          kind: string
          language_code: string | null
          latitude: number | null
          longitude: number | null
          name: string
          parent_id: string | null
          population: number | null
          status: Database["public"]["Enums"]["taxonomy_status"]
          timezone: string | null
        }
        Insert: {
          admin_code?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          geo?: unknown
          id?: string
          kind: string
          language_code?: string | null
          latitude?: number | null
          longitude?: number | null
          name: string
          parent_id?: string | null
          population?: number | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
          timezone?: string | null
        }
        Update: {
          admin_code?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          geo?: unknown
          id?: string
          kind?: string
          language_code?: string | null
          latitude?: number | null
          longitude?: number | null
          name?: string
          parent_id?: string | null
          population?: number | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
          timezone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "locations_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "locations_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "locations_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      match_events: {
        Row: {
          company_id: string
          engine_version: string | null
          event: string
          id: number
          job_id: string
          occurred_at: string
          person_id: string | null
          rank: number | null
          score: number | null
          surface: string
          work_identity_id: string | null
        }
        Insert: {
          company_id: string
          engine_version?: string | null
          event: string
          id?: never
          job_id: string
          occurred_at?: string
          person_id?: string | null
          rank?: number | null
          score?: number | null
          surface: string
          work_identity_id?: string | null
        }
        Update: {
          company_id?: string
          engine_version?: string | null
          event?: string
          id?: never
          job_id?: string
          occurred_at?: string
          person_id?: string | null
          rank?: number | null
          score?: number | null
          surface?: string
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "match_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_events_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_events_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_events_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      matches: {
        Row: {
          computed_at: string
          eligible: boolean
          engine_version: string
          feature_vector: Json
          gate_failures: string[]
          id: string
          job_id: string
          person_id: string
          score: number
          weight_profile_id: string | null
          work_identity_id: string
        }
        Insert: {
          computed_at?: string
          eligible?: boolean
          engine_version: string
          feature_vector: Json
          gate_failures?: string[]
          id?: string
          job_id: string
          person_id: string
          score: number
          weight_profile_id?: string | null
          work_identity_id: string
        }
        Update: {
          computed_at?: string
          eligible?: boolean
          engine_version?: string
          feature_vector?: Json
          gate_failures?: string[]
          id?: string
          job_id?: string
          person_id?: string
          score?: number
          weight_profile_id?: string | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "matches_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_weight_profile_id_fkey"
            columns: ["weight_profile_id"]
            isOneToOne: false
            referencedRelation: "weight_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matches_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      meet_abuse_reports: {
        Row: {
          created_at: string
          details: string | null
          id: string
          interview_id: string
          reason: string
          reported_person_id: string | null
          reporter_id: string
          status: string
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: string
          interview_id: string
          reason: string
          reported_person_id?: string | null
          reporter_id: string
          status?: string
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: string
          interview_id?: string
          reason?: string
          reported_person_id?: string | null
          reporter_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "meet_abuse_reports_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meet_abuse_reports_reported_person_id_fkey"
            columns: ["reported_person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meet_abuse_reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      meet_events: {
        Row: {
          actor_id: string | null
          event: string
          id: number
          interview_id: string
          metadata: Json
          occurred_at: string
          subject_person_id: string | null
        }
        Insert: {
          actor_id?: string | null
          event: string
          id?: never
          interview_id: string
          metadata?: Json
          occurred_at?: string
          subject_person_id?: string | null
        }
        Update: {
          actor_id?: string | null
          event?: string
          id?: never
          interview_id?: string
          metadata?: Json
          occurred_at?: string
          subject_person_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "meet_events_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
        ]
      }
      meet_messages: {
        Row: {
          body: string
          id: number
          interview_id: string
          sender_id: string
          sender_name: string | null
          sent_at: string
        }
        Insert: {
          body: string
          id?: never
          interview_id: string
          sender_id: string
          sender_name?: string | null
          sent_at?: string
        }
        Update: {
          body?: string
          id?: never
          interview_id?: string
          sender_id?: string
          sender_name?: string | null
          sent_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meet_messages_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meet_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          action_payload: Json | null
          action_type: string | null
          body: string | null
          conversation_id: string
          document_id: string | null
          id: number
          kind: Database["public"]["Enums"]["message_kind"]
          read_at: string | null
          sender_person_id: string | null
          sender_type: Database["public"]["Enums"]["actor_type"]
          sent_at: string
        }
        Insert: {
          action_payload?: Json | null
          action_type?: string | null
          body?: string | null
          conversation_id: string
          document_id?: string | null
          id?: number
          kind?: Database["public"]["Enums"]["message_kind"]
          read_at?: string | null
          sender_person_id?: string | null
          sender_type: Database["public"]["Enums"]["actor_type"]
          sent_at?: string
        }
        Update: {
          action_payload?: Json | null
          action_type?: string | null
          body?: string | null
          conversation_id?: string
          document_id?: string | null
          id?: number
          kind?: Database["public"]["Enums"]["message_kind"]
          read_at?: string | null
          sender_person_id?: string | null
          sender_type?: Database["public"]["Enums"]["actor_type"]
          sent_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_sender_person_id_fkey"
            columns: ["sender_person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      mobility_profiles: {
        Row: {
          authorization_visibility: string
          citizenships: string[]
          countries_willing_to_work: string[]
          current_country: string | null
          earliest_relocation_date: string | null
          open_to_relocation: boolean
          person_id: string
          preferred_city_ids: string[]
          preferred_countries: string[]
          relocation_assistance_required: boolean
          remote_preference: string
          requires_sponsorship: boolean | null
          timezone: string | null
          updated_at: string
        }
        Insert: {
          authorization_visibility?: string
          citizenships?: string[]
          countries_willing_to_work?: string[]
          current_country?: string | null
          earliest_relocation_date?: string | null
          open_to_relocation?: boolean
          person_id: string
          preferred_city_ids?: string[]
          preferred_countries?: string[]
          relocation_assistance_required?: boolean
          remote_preference?: string
          requires_sponsorship?: boolean | null
          timezone?: string | null
          updated_at?: string
        }
        Update: {
          authorization_visibility?: string
          citizenships?: string[]
          countries_willing_to_work?: string[]
          current_country?: string | null
          earliest_relocation_date?: string | null
          open_to_relocation?: boolean
          person_id?: string
          preferred_city_ids?: string[]
          preferred_countries?: string[]
          relocation_assistance_required?: boolean
          remote_preference?: string
          requires_sponsorship?: boolean | null
          timezone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "mobility_profiles_current_country_fkey"
            columns: ["current_country"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "mobility_profiles_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: true
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_actions: {
        Row: {
          action: Database["public"]["Enums"]["moderation_action"]
          actor_id: string | null
          created_at: string
          expires_at: string | null
          id: string
          reason: string
          report_id: string | null
          reversed_at: string | null
          subject_id: string
          subject_type: string
        }
        Insert: {
          action: Database["public"]["Enums"]["moderation_action"]
          actor_id?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          reason: string
          report_id?: string | null
          reversed_at?: string | null
          subject_id: string
          subject_type: string
        }
        Update: {
          action?: Database["public"]["Enums"]["moderation_action"]
          actor_id?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          reason?: string
          report_id?: string | null
          reversed_at?: string | null
          subject_id?: string
          subject_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "moderation_actions_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_actions_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "reports"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          email_enabled: boolean
          muted_types: Database["public"]["Enums"]["notification_type"][]
          person_id: string
          push_enabled: boolean
          quiet_hours_end: number | null
          quiet_hours_start: number | null
          sms_enabled: boolean
          updated_at: string
          whatsapp_enabled: boolean
        }
        Insert: {
          email_enabled?: boolean
          muted_types?: Database["public"]["Enums"]["notification_type"][]
          person_id: string
          push_enabled?: boolean
          quiet_hours_end?: number | null
          quiet_hours_start?: number | null
          sms_enabled?: boolean
          updated_at?: string
          whatsapp_enabled?: boolean
        }
        Update: {
          email_enabled?: boolean
          muted_types?: Database["public"]["Enums"]["notification_type"][]
          person_id?: string
          push_enabled?: boolean
          quiet_hours_end?: number | null
          quiet_hours_start?: number | null
          sms_enabled?: boolean
          updated_at?: string
          whatsapp_enabled?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: true
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          deeplink: string | null
          entity_id: string | null
          entity_type: string | null
          id: number
          person_id: string
          read_at: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
        }
        Insert: {
          body?: string | null
          created_at?: string
          deeplink?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: number
          person_id: string
          read_at?: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
        }
        Update: {
          body?: string | null
          created_at?: string
          deeplink?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: number
          person_id?: string
          read_at?: string | null
          title?: string
          type?: Database["public"]["Enums"]["notification_type"]
        }
        Relationships: [
          {
            foreignKeyName: "notifications_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      offers: {
        Row: {
          application_id: string
          benefits: Json
          company_id: string
          conditions: string | null
          contract_document_id: string | null
          created_at: string
          created_by: string | null
          decline_reason: string | null
          expires_at: string | null
          hours_per_week: number | null
          id: string
          job_id: string
          location_text: string | null
          pay_amount: number | null
          pay_basis: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency: string | null
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          responded_at: string | null
          sent_at: string | null
          shift_types: Database["public"]["Enums"]["shift_type"][]
          start_date: string | null
          status: Database["public"]["Enums"]["offer_status"]
          title: string
          updated_at: string
          viewed_at: string | null
          work_type: Database["public"]["Enums"]["work_type"] | null
          workplace_type: Database["public"]["Enums"]["workplace_type"] | null
        }
        Insert: {
          application_id: string
          benefits?: Json
          company_id: string
          conditions?: string | null
          contract_document_id?: string | null
          created_at?: string
          created_by?: string | null
          decline_reason?: string | null
          expires_at?: string | null
          hours_per_week?: number | null
          id?: string
          job_id: string
          location_text?: string | null
          pay_amount?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id: string
          responded_at?: string | null
          sent_at?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          start_date?: string | null
          status?: Database["public"]["Enums"]["offer_status"]
          title: string
          updated_at?: string
          viewed_at?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Update: {
          application_id?: string
          benefits?: Json
          company_id?: string
          conditions?: string | null
          contract_document_id?: string | null
          created_at?: string
          created_by?: string | null
          decline_reason?: string | null
          expires_at?: string | null
          hours_per_week?: number | null
          id?: string
          job_id?: string
          location_text?: string | null
          pay_amount?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          person_id?: string
          responded_at?: string | null
          sent_at?: string | null
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          start_date?: string | null
          status?: Database["public"]["Enums"]["offer_status"]
          title?: string
          updated_at?: string
          viewed_at?: string | null
          work_type?: Database["public"]["Enums"]["work_type"] | null
          workplace_type?: Database["public"]["Enums"]["workplace_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "offers_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_contract_document_id_fkey"
            columns: ["contract_document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "offers_pay_currency_currency_fk"
            columns: ["pay_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "offers_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      outbound_messages: {
        Row: {
          attempts: number
          channel: string
          created_at: string
          dedupe_key: string | null
          id: string
          last_error: string | null
          payload: Json
          person_id: string | null
          provider_message_id: string | null
          send_after: string
          sent_at: string | null
          status: string
          subject: string | null
          template: string
          to_address: string | null
        }
        Insert: {
          attempts?: number
          channel: string
          created_at?: string
          dedupe_key?: string | null
          id?: string
          last_error?: string | null
          payload?: Json
          person_id?: string | null
          provider_message_id?: string | null
          send_after?: string
          sent_at?: string | null
          status?: string
          subject?: string | null
          template: string
          to_address?: string | null
        }
        Update: {
          attempts?: number
          channel?: string
          created_at?: string
          dedupe_key?: string | null
          id?: string
          last_error?: string | null
          payload?: Json
          person_id?: string | null
          provider_message_id?: string | null
          send_after?: string
          sent_at?: string | null
          status?: string
          subject?: string | null
          template?: string
          to_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "outbound_messages_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      overtime_policies: {
        Row: {
          company_id: string
          country_code: string | null
          created_at: string
          daily_threshold_minutes: number | null
          id: string
          max_overtime_minutes_week: number | null
          multiplier: number
          name: string
          notes: string | null
          standard_minutes_per_day: number
          standard_minutes_per_week: number
          weekly_threshold_minutes: number | null
        }
        Insert: {
          company_id: string
          country_code?: string | null
          created_at?: string
          daily_threshold_minutes?: number | null
          id?: string
          max_overtime_minutes_week?: number | null
          multiplier?: number
          name: string
          notes?: string | null
          standard_minutes_per_day?: number
          standard_minutes_per_week?: number
          weekly_threshold_minutes?: number | null
        }
        Update: {
          company_id?: string
          country_code?: string | null
          created_at?: string
          daily_threshold_minutes?: number | null
          id?: string
          max_overtime_minutes_week?: number | null
          multiplier?: number
          name?: string
          notes?: string | null
          standard_minutes_per_day?: number
          standard_minutes_per_week?: number
          weekly_threshold_minutes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "overtime_policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "overtime_policies_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
        ]
      }
      pay_components: {
        Row: {
          amount: number
          applies_to_shift_types: Database["public"]["Enums"]["shift_type"][]
          assignment_id: string | null
          basis: string
          created_at: string
          created_by: string | null
          id: string
          kind: string
          name: string
          requirement_id: string | null
        }
        Insert: {
          amount: number
          applies_to_shift_types?: Database["public"]["Enums"]["shift_type"][]
          assignment_id?: string | null
          basis: string
          created_at?: string
          created_by?: string | null
          id?: string
          kind: string
          name: string
          requirement_id?: string | null
        }
        Update: {
          amount?: number
          applies_to_shift_types?: Database["public"]["Enums"]["shift_type"][]
          assignment_id?: string | null
          basis?: string
          created_at?: string
          created_by?: string | null
          id?: string
          kind?: string
          name?: string
          requirement_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pay_components_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pay_components_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pay_components_requirement_id_fkey"
            columns: ["requirement_id"]
            isOneToOne: false
            referencedRelation: "workforce_requirements"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_records: {
        Row: {
          amount: number
          company_id: string
          created_at: string
          created_by: string | null
          currency: string
          earning_id: string
          failure_reason: string | null
          id: string
          paid_at: string | null
          person_id: string
          provider: string | null
          provider_reference: string | null
          scheduled_for: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount: number
          company_id: string
          created_at?: string
          created_by?: string | null
          currency: string
          earning_id: string
          failure_reason?: string | null
          id?: string
          paid_at?: string | null
          person_id: string
          provider?: string | null
          provider_reference?: string | null
          scheduled_for?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency?: string
          earning_id?: string
          failure_reason?: string | null
          id?: string
          paid_at?: string | null
          person_id?: string
          provider?: string | null
          provider_reference?: string | null
          scheduled_for?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_records_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_records_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_records_currency_currency_fk"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "payment_records_earning_id_fkey"
            columns: ["earning_id"]
            isOneToOne: false
            referencedRelation: "earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_records_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_attributes: {
        Row: {
          attribute_id: string
          created_at: string
          id: string
          person_id: string
          source: Database["public"]["Enums"]["source_type"]
          value_bool: boolean | null
          value_date: string | null
          value_json: Json | null
          value_number: number | null
          value_text: string | null
          work_identity_id: string
        }
        Insert: {
          attribute_id: string
          created_at?: string
          id?: string
          person_id: string
          source?: Database["public"]["Enums"]["source_type"]
          value_bool?: boolean | null
          value_date?: string | null
          value_json?: Json | null
          value_number?: number | null
          value_text?: string | null
          work_identity_id: string
        }
        Update: {
          attribute_id?: string
          created_at?: string
          id?: string
          person_id?: string
          source?: Database["public"]["Enums"]["source_type"]
          value_bool?: boolean | null
          value_date?: string | null
          value_json?: Json | null
          value_number?: number | null
          value_text?: string | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "person_attributes_attribute_id_fkey"
            columns: ["attribute_id"]
            isOneToOne: false
            referencedRelation: "profile_attributes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_attributes_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_attributes_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_credentials: {
        Row: {
          created_at: string
          credential_number: string | null
          credential_type_id: string | null
          document_id: string | null
          expires_on: string | null
          id: string
          is_verified: boolean
          issued_on: string | null
          issuer: string | null
          name: string
          person_id: string
          verification_url: string | null
        }
        Insert: {
          created_at?: string
          credential_number?: string | null
          credential_type_id?: string | null
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuer?: string | null
          name: string
          person_id: string
          verification_url?: string | null
        }
        Update: {
          created_at?: string
          credential_number?: string | null
          credential_type_id?: string | null
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuer?: string | null
          name?: string
          person_id?: string
          verification_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "person_credentials_credential_type_id_fkey"
            columns: ["credential_type_id"]
            isOneToOne: false
            referencedRelation: "credential_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_credentials_document_fk"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_credentials_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_languages: {
        Row: {
          can_read: boolean | null
          can_write: boolean | null
          language_code: string
          person_id: string
          proficiency: Database["public"]["Enums"]["language_proficiency"]
        }
        Insert: {
          can_read?: boolean | null
          can_write?: boolean | null
          language_code: string
          person_id: string
          proficiency: Database["public"]["Enums"]["language_proficiency"]
        }
        Update: {
          can_read?: boolean | null
          can_write?: boolean | null
          language_code?: string
          person_id?: string
          proficiency?: Database["public"]["Enums"]["language_proficiency"]
        }
        Relationships: [
          {
            foreignKeyName: "person_languages_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "person_languages_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_licenses: {
        Row: {
          country_code: string | null
          created_at: string
          document_id: string | null
          expires_on: string | null
          id: string
          is_verified: boolean
          issued_on: string | null
          issuing_body: string | null
          license_class: string | null
          license_number: string | null
          license_type_id: string | null
          name: string
          person_id: string
          verification_status: Database["public"]["Enums"]["verification_status"]
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuing_body?: string | null
          license_class?: string | null
          license_number?: string | null
          license_type_id?: string | null
          name: string
          person_id: string
          verification_status?: Database["public"]["Enums"]["verification_status"]
        }
        Update: {
          country_code?: string | null
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          issued_on?: string | null
          issuing_body?: string | null
          license_class?: string | null
          license_number?: string | null
          license_type_id?: string | null
          name?: string
          person_id?: string
          verification_status?: Database["public"]["Enums"]["verification_status"]
        }
        Relationships: [
          {
            foreignKeyName: "person_licenses_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "person_licenses_document_fk"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_licenses_license_type_id_fkey"
            columns: ["license_type_id"]
            isOneToOne: false
            referencedRelation: "license_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_licenses_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_location_preferences: {
        Row: {
          country_code: string | null
          created_at: string
          id: string
          kind: string
          location_id: string | null
          person_id: string
          priority: number
          radius_km: number | null
          work_identity_id: string
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          id?: string
          kind: string
          location_id?: string | null
          person_id: string
          priority?: number
          radius_km?: number | null
          work_identity_id: string
        }
        Update: {
          country_code?: string | null
          created_at?: string
          id?: string
          kind?: string
          location_id?: string | null
          person_id?: string
          priority?: number
          radius_km?: number | null
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "person_location_preferences_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "person_location_preferences_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_location_preferences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_location_preferences_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_professions: {
        Row: {
          created_at: string
          months_experience: number | null
          person_id: string
          priority: number
          profession_id: string
          relationship: string
          work_identity_id: string
        }
        Insert: {
          created_at?: string
          months_experience?: number | null
          person_id: string
          priority?: number
          profession_id: string
          relationship: string
          work_identity_id: string
        }
        Update: {
          created_at?: string
          months_experience?: number | null
          person_id?: string
          priority?: number
          profession_id?: string
          relationship?: string
          work_identity_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "person_professions_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_professions_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_professions_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_references: {
        Row: {
          company_name: string | null
          created_at: string
          email: string | null
          id: string
          is_verified: boolean
          name: string
          person_id: string
          phone: string | null
          relationship: string | null
        }
        Insert: {
          company_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          is_verified?: boolean
          name: string
          person_id: string
          phone?: string | null
          relationship?: string | null
        }
        Update: {
          company_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          is_verified?: boolean
          name?: string
          person_id?: string
          phone?: string | null
          relationship?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "person_references_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      person_skills: {
        Row: {
          created_at: string
          evidence_refs: Json
          evidence_type: Database["public"]["Enums"]["evidence_type"]
          id: string
          is_verified: boolean
          last_used_on: string | null
          months_used: number | null
          person_id: string
          proficiency: Database["public"]["Enums"]["proficiency_level"] | null
          skill_id: string
          source: Database["public"]["Enums"]["source_type"]
          work_identity_id: string | null
        }
        Insert: {
          created_at?: string
          evidence_refs?: Json
          evidence_type?: Database["public"]["Enums"]["evidence_type"]
          id?: string
          is_verified?: boolean
          last_used_on?: string | null
          months_used?: number | null
          person_id: string
          proficiency?: Database["public"]["Enums"]["proficiency_level"] | null
          skill_id: string
          source?: Database["public"]["Enums"]["source_type"]
          work_identity_id?: string | null
        }
        Update: {
          created_at?: string
          evidence_refs?: Json
          evidence_type?: Database["public"]["Enums"]["evidence_type"]
          id?: string
          is_verified?: boolean
          last_used_on?: string | null
          months_used?: number | null
          person_id?: string
          proficiency?: Database["public"]["Enums"]["proficiency_level"] | null
          skill_id?: string
          source?: Database["public"]["Enums"]["source_type"]
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "person_skills_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_skills_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      person_work_preferences: {
        Row: {
          availability: Database["public"]["Enums"]["availability_window"]
          available_from: string | null
          available_until: string | null
          current_pay_amount: number | null
          current_pay_period: Database["public"]["Enums"]["pay_period"] | null
          expected_pay_amount: number | null
          expected_pay_period: Database["public"]["Enums"]["pay_period"] | null
          max_travel_km: number | null
          max_weekly_hours: number | null
          min_outreach_pay_amount: number | null
          min_outreach_pay_period:
            | Database["public"]["Enums"]["pay_period"]
            | null
          minimum_pay_amount: number | null
          minimum_pay_period: Database["public"]["Enums"]["pay_period"] | null
          needs_accommodation: boolean
          needs_transport: boolean
          notice_period_days: number | null
          pay_basis: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency: string | null
          person_id: string
          preferred_days: number[]
          preferred_end_time: string | null
          preferred_start_time: string | null
          seeking: boolean
          shift_types: Database["public"]["Enums"]["shift_type"][]
          updated_at: string
          willing_to_relocate: boolean
          willing_to_travel: boolean
          work_identity_id: string
          work_types: Database["public"]["Enums"]["work_type"][]
          workplace_types: Database["public"]["Enums"]["workplace_type"][]
        }
        Insert: {
          availability?: Database["public"]["Enums"]["availability_window"]
          available_from?: string | null
          available_until?: string | null
          current_pay_amount?: number | null
          current_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          expected_pay_amount?: number | null
          expected_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          max_travel_km?: number | null
          max_weekly_hours?: number | null
          min_outreach_pay_amount?: number | null
          min_outreach_pay_period?:
            | Database["public"]["Enums"]["pay_period"]
            | null
          minimum_pay_amount?: number | null
          minimum_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          needs_accommodation?: boolean
          needs_transport?: boolean
          notice_period_days?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          person_id: string
          preferred_days?: number[]
          preferred_end_time?: string | null
          preferred_start_time?: string | null
          seeking?: boolean
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          updated_at?: string
          willing_to_relocate?: boolean
          willing_to_travel?: boolean
          work_identity_id: string
          work_types?: Database["public"]["Enums"]["work_type"][]
          workplace_types?: Database["public"]["Enums"]["workplace_type"][]
        }
        Update: {
          availability?: Database["public"]["Enums"]["availability_window"]
          available_from?: string | null
          available_until?: string | null
          current_pay_amount?: number | null
          current_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          expected_pay_amount?: number | null
          expected_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          max_travel_km?: number | null
          max_weekly_hours?: number | null
          min_outreach_pay_amount?: number | null
          min_outreach_pay_period?:
            | Database["public"]["Enums"]["pay_period"]
            | null
          minimum_pay_amount?: number | null
          minimum_pay_period?: Database["public"]["Enums"]["pay_period"] | null
          needs_accommodation?: boolean
          needs_transport?: boolean
          notice_period_days?: number | null
          pay_basis?: Database["public"]["Enums"]["pay_basis"] | null
          pay_currency?: string | null
          person_id?: string
          preferred_days?: number[]
          preferred_end_time?: string | null
          preferred_start_time?: string | null
          seeking?: boolean
          shift_types?: Database["public"]["Enums"]["shift_type"][]
          updated_at?: string
          willing_to_relocate?: boolean
          willing_to_travel?: boolean
          work_identity_id?: string
          work_types?: Database["public"]["Enums"]["work_type"][]
          workplace_types?: Database["public"]["Enums"]["workplace_type"][]
        }
        Relationships: [
          {
            foreignKeyName: "person_work_preferences_pay_currency_currency_fk"
            columns: ["pay_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "person_work_preferences_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_work_preferences_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: true
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      persons: {
        Row: {
          about: string | null
          avatar_url: string | null
          country_code: string | null
          created_at: string
          date_of_birth: string | null
          deleted_at: string | null
          discoverability: Database["public"]["Enums"]["discoverability"]
          display_name: string | null
          email: string | null
          family_name: string | null
          geo: unknown
          given_name: string | null
          headline: string | null
          highest_education:
            | Database["public"]["Enums"]["education_level"]
            | null
          id: string
          last_active_at: string | null
          locale: string
          location_id: string | null
          location_text: string | null
          onboarding_stage: string
          phone: string | null
          profile_slug: string | null
          timezone: string | null
          updated_at: string
        }
        Insert: {
          about?: string | null
          avatar_url?: string | null
          country_code?: string | null
          created_at?: string
          date_of_birth?: string | null
          deleted_at?: string | null
          discoverability?: Database["public"]["Enums"]["discoverability"]
          display_name?: string | null
          email?: string | null
          family_name?: string | null
          geo?: unknown
          given_name?: string | null
          headline?: string | null
          highest_education?:
            | Database["public"]["Enums"]["education_level"]
            | null
          id: string
          last_active_at?: string | null
          locale?: string
          location_id?: string | null
          location_text?: string | null
          onboarding_stage?: string
          phone?: string | null
          profile_slug?: string | null
          timezone?: string | null
          updated_at?: string
        }
        Update: {
          about?: string | null
          avatar_url?: string | null
          country_code?: string | null
          created_at?: string
          date_of_birth?: string | null
          deleted_at?: string | null
          discoverability?: Database["public"]["Enums"]["discoverability"]
          display_name?: string | null
          email?: string | null
          family_name?: string | null
          geo?: unknown
          given_name?: string | null
          headline?: string | null
          highest_education?:
            | Database["public"]["Enums"]["education_level"]
            | null
          id?: string
          last_active_at?: string | null
          locale?: string
          location_id?: string | null
          location_text?: string | null
          onboarding_stage?: string
          phone?: string | null
          profile_slug?: string | null
          timezone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "persons_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "persons_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      placements: {
        Row: {
          agency_id: string
          application_id: string | null
          client_id: string
          created_at: string
          employment_id: string | null
          fee_amount: number | null
          fee_currency: string | null
          guarantee_ends_on: string | null
          id: string
          job_order_id: string
          notes: string | null
          person_id: string
          start_date: string | null
          status: string
          submission_id: string
          title: string | null
          updated_at: string
        }
        Insert: {
          agency_id: string
          application_id?: string | null
          client_id: string
          created_at?: string
          employment_id?: string | null
          fee_amount?: number | null
          fee_currency?: string | null
          guarantee_ends_on?: string | null
          id?: string
          job_order_id: string
          notes?: string | null
          person_id: string
          start_date?: string | null
          status?: string
          submission_id: string
          title?: string | null
          updated_at?: string
        }
        Update: {
          agency_id?: string
          application_id?: string | null
          client_id?: string
          created_at?: string
          employment_id?: string | null
          fee_amount?: number | null
          fee_currency?: string | null
          guarantee_ends_on?: string | null
          id?: string
          job_order_id?: string
          notes?: string | null
          person_id?: string
          start_date?: string | null
          status?: string
          submission_id?: string
          title?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "placements_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "placements_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "placements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "placements_employment_id_fkey"
            columns: ["employment_id"]
            isOneToOne: false
            referencedRelation: "employments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "placements_fee_currency_currency_fk"
            columns: ["fee_currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "placements_job_order_id_fkey"
            columns: ["job_order_id"]
            isOneToOne: false
            referencedRelation: "job_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "placements_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "placements_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: true
            referencedRelation: "candidate_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_admins: {
        Row: {
          expires_at: string | null
          granted_at: string
          granted_by: string | null
          is_active: boolean
          person_id: string
          role: string
        }
        Insert: {
          expires_at?: string | null
          granted_at?: string
          granted_by?: string | null
          is_active?: boolean
          person_id: string
          role: string
        }
        Update: {
          expires_at?: string | null
          granted_at?: string
          granted_by?: string | null
          is_active?: boolean
          person_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_admins_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_admins_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: true
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      profession_aliases: {
        Row: {
          alias: string
          created_at: string
          id: string
          locale: string | null
          occurrences: number
          profession_id: string | null
          status: Database["public"]["Enums"]["taxonomy_status"]
        }
        Insert: {
          alias: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          profession_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Update: {
          alias?: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          profession_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Relationships: [
          {
            foreignKeyName: "profession_aliases_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      profession_skills: {
        Row: {
          importance: number
          profession_id: string
          skill_id: string
          source: Database["public"]["Enums"]["source_type"]
        }
        Insert: {
          importance: number
          profession_id: string
          skill_id: string
          source?: Database["public"]["Enums"]["source_type"]
        }
        Update: {
          importance?: number
          profession_id?: string
          skill_id?: string
          source?: Database["public"]["Enums"]["source_type"]
        }
        Relationships: [
          {
            foreignKeyName: "profession_skills_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profession_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      profession_transitions: {
        Row: {
          from_profession_id: string
          last_computed_at: string | null
          median_months: number | null
          median_pay_delta_pct: number | null
          observed_count: number
          prior_strength: number
          to_profession_id: string
        }
        Insert: {
          from_profession_id: string
          last_computed_at?: string | null
          median_months?: number | null
          median_pay_delta_pct?: number | null
          observed_count?: number
          prior_strength?: number
          to_profession_id: string
        }
        Update: {
          from_profession_id?: string
          last_computed_at?: string | null
          median_months?: number | null
          median_pay_delta_pct?: number | null
          observed_count?: number
          prior_strength?: number
          to_profession_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profession_transitions_from_profession_id_fkey"
            columns: ["from_profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profession_transitions_to_profession_id_fkey"
            columns: ["to_profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      professions: {
        Row: {
          category_id: string
          created_at: string
          description: string | null
          embedding: string | null
          external_ids: Json
          id: string
          is_entry_level_friendly: boolean
          merged_into: string | null
          name: string
          requires_license: boolean
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          typical_education_level:
            | Database["public"]["Enums"]["education_level"]
            | null
          typical_work_types: Database["public"]["Enums"]["work_type"][]
        }
        Insert: {
          category_id: string
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          is_entry_level_friendly?: boolean
          merged_into?: string | null
          name: string
          requires_license?: boolean
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          typical_education_level?:
            | Database["public"]["Enums"]["education_level"]
            | null
          typical_work_types?: Database["public"]["Enums"]["work_type"][]
        }
        Update: {
          category_id?: string
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          is_entry_level_friendly?: boolean
          merged_into?: string | null
          name?: string
          requires_license?: boolean
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          typical_education_level?:
            | Database["public"]["Enums"]["education_level"]
            | null
          typical_work_types?: Database["public"]["Enums"]["work_type"][]
        }
        Relationships: [
          {
            foreignKeyName: "professions_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "professions_merged_into_fkey"
            columns: ["merged_into"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_attributes: {
        Row: {
          category_id: string | null
          created_at: string
          data_type: Database["public"]["Enums"]["attribute_data_type"]
          help_text: string | null
          id: string
          is_filterable: boolean
          is_required: boolean
          label: string
          options: Json
          position: number
          profession_id: string | null
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          unit: string | null
          usable_as_requirement: boolean
        }
        Insert: {
          category_id?: string | null
          created_at?: string
          data_type: Database["public"]["Enums"]["attribute_data_type"]
          help_text?: string | null
          id?: string
          is_filterable?: boolean
          is_required?: boolean
          label: string
          options?: Json
          position?: number
          profession_id?: string | null
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          unit?: string | null
          usable_as_requirement?: boolean
        }
        Update: {
          category_id?: string | null
          created_at?: string
          data_type?: Database["public"]["Enums"]["attribute_data_type"]
          help_text?: string | null
          id?: string
          is_filterable?: boolean
          is_required?: boolean
          label?: string
          options?: Json
          position?: number
          profession_id?: string | null
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          unit?: string | null
          usable_as_requirement?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "profile_attributes_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_attributes_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_views: {
        Row: {
          context_job_id: string | null
          id: string
          person_id: string
          viewed_at: string
          viewer_company_id: string | null
          viewer_person_id: string | null
          work_identity_id: string | null
        }
        Insert: {
          context_job_id?: string | null
          id?: string
          person_id: string
          viewed_at?: string
          viewer_company_id?: string | null
          viewer_person_id?: string | null
          work_identity_id?: string | null
        }
        Update: {
          context_job_id?: string | null
          id?: string
          person_id?: string
          viewed_at?: string
          viewer_company_id?: string | null
          viewer_person_id?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profile_views_context_job_id_fkey"
            columns: ["context_job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_viewer_company_id_fkey"
            columns: ["viewer_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_viewer_person_id_fkey"
            columns: ["viewer_person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_views_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      project_skills: {
        Row: {
          project_id: string
          skill_id: string
        }
        Insert: {
          project_id: string
          skill_id: string
        }
        Update: {
          project_id?: string
          skill_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_skills_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_skills_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          created_at: string
          description: string | null
          ended_on: string | null
          id: string
          media: Json
          person_id: string
          role: string | null
          started_on: string | null
          title: string
          url: string | null
          work_identity_id: string | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          ended_on?: string | null
          id?: string
          media?: Json
          person_id: string
          role?: string | null
          started_on?: string | null
          title: string
          url?: string | null
          work_identity_id?: string | null
        }
        Update: {
          created_at?: string
          description?: string | null
          ended_on?: string | null
          id?: string
          media?: Json
          person_id?: string
          role?: string | null
          started_on?: string | null
          title?: string
          url?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "projects_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "projects_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          assigned_to: string | null
          created_at: string
          details: string | null
          id: string
          reason: Database["public"]["Enums"]["report_reason"]
          reporter_id: string | null
          resolution: Database["public"]["Enums"]["moderation_action"] | null
          resolution_note: string | null
          resolved_at: string | null
          status: Database["public"]["Enums"]["report_status"]
          subject_id: string
          subject_type: string
        }
        Insert: {
          assigned_to?: string | null
          created_at?: string
          details?: string | null
          id?: string
          reason: Database["public"]["Enums"]["report_reason"]
          reporter_id?: string | null
          resolution?: Database["public"]["Enums"]["moderation_action"] | null
          resolution_note?: string | null
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["report_status"]
          subject_id: string
          subject_type: string
        }
        Update: {
          assigned_to?: string | null
          created_at?: string
          details?: string | null
          id?: string
          reason?: Database["public"]["Enums"]["report_reason"]
          reporter_id?: string | null
          resolution?: Database["public"]["Enums"]["moderation_action"] | null
          resolution_note?: string | null
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["report_status"]
          subject_id?: string
          subject_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "reports_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_jobs: {
        Row: {
          created_at: string
          job_id: string
          person_id: string
        }
        Insert: {
          created_at?: string
          job_id: string
          person_id: string
        }
        Update: {
          created_at?: string
          job_id?: string
          person_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saved_jobs_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_jobs_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_searches: {
        Row: {
          alert_cadence: string
          created_at: string
          facets: Json
          id: string
          last_alerted_at: string | null
          name: string
          person_id: string
          query_text: string | null
          work_identity_id: string | null
        }
        Insert: {
          alert_cadence?: string
          created_at?: string
          facets?: Json
          id?: string
          last_alerted_at?: string | null
          name: string
          person_id: string
          query_text?: string | null
          work_identity_id?: string | null
        }
        Update: {
          alert_cadence?: string
          created_at?: string
          facets?: Json
          id?: string
          last_alerted_at?: string | null
          name?: string
          person_id?: string
          query_text?: string | null
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "saved_searches_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_searches_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_codes: {
        Row: {
          code: string
          created_at: string
          shift_id: string
        }
        Insert: {
          code: string
          created_at?: string
          shift_id: string
        }
        Update: {
          code?: string
          created_at?: string
          shift_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_codes_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: true
            referencedRelation: "shifts"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_templates: {
        Row: {
          break_minutes: number
          created_at: string
          created_by: string | null
          days_of_week: number[]
          end_time: string
          id: string
          name: string
          required_workers: number
          requirement_id: string
          shift_type: Database["public"]["Enums"]["shift_type"] | null
          start_time: string
          status: string
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          break_minutes?: number
          created_at?: string
          created_by?: string | null
          days_of_week: number[]
          end_time: string
          id?: string
          name: string
          required_workers?: number
          requirement_id: string
          shift_type?: Database["public"]["Enums"]["shift_type"] | null
          start_time: string
          status?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          break_minutes?: number
          created_at?: string
          created_by?: string | null
          days_of_week?: number[]
          end_time?: string
          id?: string
          name?: string
          required_workers?: number
          requirement_id?: string
          shift_type?: Database["public"]["Enums"]["shift_type"] | null
          start_time?: string
          status?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "shift_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_templates_requirement_id_fkey"
            columns: ["requirement_id"]
            isOneToOne: false
            referencedRelation: "workforce_requirements"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_workers: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          assignment_id: string
          ends_at: string
          id: string
          person_id: string
          reminder_sent_at: string | null
          responded_at: string | null
          shift_id: string
          starts_at: string
          status: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          assignment_id: string
          ends_at: string
          id?: string
          person_id: string
          reminder_sent_at?: string | null
          responded_at?: string | null
          shift_id: string
          starts_at: string
          status?: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          assignment_id?: string
          ends_at?: string
          id?: string
          person_id?: string
          reminder_sent_at?: string | null
          responded_at?: string | null
          shift_id?: string
          starts_at?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_workers_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_workers_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_workers_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_workers_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shifts"
            referencedColumns: ["id"]
          },
        ]
      }
      shifts: {
        Row: {
          break_minutes: number
          cancel_reason: string | null
          company_id: string
          created_at: string
          created_by: string | null
          ends_at: string
          id: string
          instructions: string | null
          kind: string
          location_id: string | null
          location_text: string | null
          required_workers: number
          requirement_id: string
          shift_type: Database["public"]["Enums"]["shift_type"] | null
          starts_at: string
          status: string
          supervisor_id: string | null
          template_id: string | null
          timezone: string
          updated_at: string
        }
        Insert: {
          break_minutes?: number
          cancel_reason?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          ends_at: string
          id?: string
          instructions?: string | null
          kind?: string
          location_id?: string | null
          location_text?: string | null
          required_workers?: number
          requirement_id: string
          shift_type?: Database["public"]["Enums"]["shift_type"] | null
          starts_at: string
          status?: string
          supervisor_id?: string | null
          template_id?: string | null
          timezone: string
          updated_at?: string
        }
        Update: {
          break_minutes?: number
          cancel_reason?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          ends_at?: string
          id?: string
          instructions?: string | null
          kind?: string
          location_id?: string | null
          location_text?: string | null
          required_workers?: number
          requirement_id?: string
          shift_type?: Database["public"]["Enums"]["shift_type"] | null
          starts_at?: string
          status?: string
          supervisor_id?: string | null
          template_id?: string | null
          timezone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "shifts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_requirement_id_fkey"
            columns: ["requirement_id"]
            isOneToOne: false
            referencedRelation: "workforce_requirements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "shift_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      skill_aliases: {
        Row: {
          alias: string
          created_at: string
          id: string
          locale: string | null
          occurrences: number
          skill_id: string | null
          status: Database["public"]["Enums"]["taxonomy_status"]
        }
        Insert: {
          alias: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          skill_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Update: {
          alias?: string
          created_at?: string
          id?: string
          locale?: string | null
          occurrences?: number
          skill_id?: string | null
          status?: Database["public"]["Enums"]["taxonomy_status"]
        }
        Relationships: [
          {
            foreignKeyName: "skill_aliases_skill_id_fkey"
            columns: ["skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      skill_relations: {
        Row: {
          from_skill_id: string
          kind: Database["public"]["Enums"]["relation_kind"]
          source: Database["public"]["Enums"]["source_type"]
          strength: number
          to_skill_id: string
        }
        Insert: {
          from_skill_id: string
          kind: Database["public"]["Enums"]["relation_kind"]
          source?: Database["public"]["Enums"]["source_type"]
          strength?: number
          to_skill_id: string
        }
        Update: {
          from_skill_id?: string
          kind?: Database["public"]["Enums"]["relation_kind"]
          source?: Database["public"]["Enums"]["source_type"]
          strength?: number
          to_skill_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "skill_relations_from_skill_id_fkey"
            columns: ["from_skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "skill_relations_to_skill_id_fkey"
            columns: ["to_skill_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      skills: {
        Row: {
          created_at: string
          description: string | null
          embedding: string | null
          external_ids: Json
          id: string
          merged_into: string | null
          name: string
          slug: string
          status: Database["public"]["Enums"]["taxonomy_status"]
          type: Database["public"]["Enums"]["skill_type"]
        }
        Insert: {
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          merged_into?: string | null
          name: string
          slug: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          type: Database["public"]["Enums"]["skill_type"]
        }
        Update: {
          created_at?: string
          description?: string | null
          embedding?: string | null
          external_ids?: Json
          id?: string
          merged_into?: string | null
          name?: string
          slug?: string
          status?: Database["public"]["Enums"]["taxonomy_status"]
          type?: Database["public"]["Enums"]["skill_type"]
        }
        Relationships: [
          {
            foreignKeyName: "skills_merged_into_fkey"
            columns: ["merged_into"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id"]
          },
        ]
      }
      support_sessions: {
        Row: {
          admin_id: string
          disclosed_at: string | null
          ended_at: string | null
          expires_at: string
          id: string
          person_id: string
          reason: string
          request_ref: string | null
          started_at: string
        }
        Insert: {
          admin_id: string
          disclosed_at?: string | null
          ended_at?: string | null
          expires_at: string
          id?: string
          person_id: string
          reason: string
          request_ref?: string | null
          started_at?: string
        }
        Update: {
          admin_id?: string
          disclosed_at?: string | null
          ended_at?: string | null
          expires_at?: string
          id?: string
          person_id?: string
          reason?: string
          request_ref?: string | null
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_sessions_admin_id_fkey"
            columns: ["admin_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_sessions_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      talent_pool_members: {
        Row: {
          added_at: string
          added_by: string | null
          note: string | null
          person_id: string
          pool_id: string
          work_identity_id: string | null
        }
        Insert: {
          added_at?: string
          added_by?: string | null
          note?: string | null
          person_id: string
          pool_id: string
          work_identity_id?: string | null
        }
        Update: {
          added_at?: string
          added_by?: string | null
          note?: string | null
          person_id?: string
          pool_id?: string
          work_identity_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "talent_pool_members_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pool_members_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pool_members_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "talent_pools"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pool_members_work_identity_id_fkey"
            columns: ["work_identity_id"]
            isOneToOne: false
            referencedRelation: "work_identities"
            referencedColumns: ["id"]
          },
        ]
      }
      talent_pools: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          name: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "talent_pools_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "talent_pools_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      timesheet_entries: {
        Row: {
          attendance_id: string | null
          created_at: string
          created_by: string | null
          id: string
          kind: string
          minutes: number
          note: string | null
          timesheet_id: string
          work_date: string
        }
        Insert: {
          attendance_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          kind: string
          minutes: number
          note?: string | null
          timesheet_id: string
          work_date: string
        }
        Update: {
          attendance_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          kind?: string
          minutes?: number
          note?: string | null
          timesheet_id?: string
          work_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "timesheet_entries_attendance_id_fkey"
            columns: ["attendance_id"]
            isOneToOne: false
            referencedRelation: "attendance_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "timesheet_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "timesheet_entries_timesheet_id_fkey"
            columns: ["timesheet_id"]
            isOneToOne: false
            referencedRelation: "timesheets"
            referencedColumns: ["id"]
          },
        ]
      }
      timesheets: {
        Row: {
          assignment_id: string
          company_id: string
          created_at: string
          days_worked: number
          id: string
          locked_at: string | null
          overtime_minutes: number
          period_end: string
          period_start: string
          person_id: string
          regular_minutes: number
          reject_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          shifts_worked: number
          status: string
          submitted_at: string | null
          total_minutes: number
          updated_at: string
        }
        Insert: {
          assignment_id: string
          company_id: string
          created_at?: string
          days_worked?: number
          id?: string
          locked_at?: string | null
          overtime_minutes?: number
          period_end: string
          period_start: string
          person_id: string
          regular_minutes?: number
          reject_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          shifts_worked?: number
          status?: string
          submitted_at?: string | null
          total_minutes?: number
          updated_at?: string
        }
        Update: {
          assignment_id?: string
          company_id?: string
          created_at?: string
          days_worked?: number
          id?: string
          locked_at?: string | null
          overtime_minutes?: number
          period_end?: string
          period_start?: string
          person_id?: string
          regular_minutes?: number
          reject_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          shifts_worked?: number
          status?: string
          submitted_at?: string | null
          total_minutes?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "timesheets_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "timesheets_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "timesheets_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "timesheets_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      verifications: {
        Row: {
          claim: Json
          created_at: string
          expires_at: string | null
          id: string
          method: Database["public"]["Enums"]["verification_method"] | null
          person_id: string | null
          provider: string | null
          revoke_reason: string | null
          revoked_at: string | null
          status: Database["public"]["Enums"]["verification_status"]
          subject_id: string
          subject_type: string
          type: Database["public"]["Enums"]["verification_type"]
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          claim?: Json
          created_at?: string
          expires_at?: string | null
          id?: string
          method?: Database["public"]["Enums"]["verification_method"] | null
          person_id?: string | null
          provider?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          status?: Database["public"]["Enums"]["verification_status"]
          subject_id: string
          subject_type: string
          type: Database["public"]["Enums"]["verification_type"]
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          claim?: Json
          created_at?: string
          expires_at?: string | null
          id?: string
          method?: Database["public"]["Enums"]["verification_method"] | null
          person_id?: string | null
          provider?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          status?: Database["public"]["Enums"]["verification_status"]
          subject_id?: string
          subject_type?: string
          type?: Database["public"]["Enums"]["verification_type"]
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "verifications_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      weight_profiles: {
        Row: {
          category_id: string | null
          created_at: string
          id: string
          is_active: boolean
          name: string
          weights: Json
        }
        Insert: {
          category_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          weights: Json
        }
        Update: {
          category_id?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          weights?: Json
        }
        Relationships: [
          {
            foreignKeyName: "weight_profiles_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      work_authorizations: {
        Row: {
          country_code: string
          created_at: string
          document_id: string | null
          expires_on: string | null
          id: string
          is_verified: boolean
          person_id: string
          requires_sponsorship: boolean | null
          status: Database["public"]["Enums"]["work_auth_status"]
          updated_at: string
          valid_from: string | null
          work_restrictions: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          person_id: string
          requires_sponsorship?: boolean | null
          status: Database["public"]["Enums"]["work_auth_status"]
          updated_at?: string
          valid_from?: string | null
          work_restrictions?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          document_id?: string | null
          expires_on?: string | null
          id?: string
          is_verified?: boolean
          person_id?: string
          requires_sponsorship?: boolean | null
          status?: Database["public"]["Enums"]["work_auth_status"]
          updated_at?: string
          valid_from?: string | null
          work_restrictions?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "work_authorizations_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "work_authorizations_document_fk"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_authorizations_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      work_identities: {
        Row: {
          about: string | null
          allow_invitations: boolean
          allow_recruiter_requests: boolean
          category_id: string | null
          completeness_score: number
          created_at: string
          discoverability: Database["public"]["Enums"]["discoverability"]
          headline: string | null
          id: string
          identity_embedding: string | null
          is_primary: boolean
          label: string
          person_id: string
          profession_id: string | null
          profession_source: Database["public"]["Enums"]["source_type"]
          status: Database["public"]["Enums"]["work_identity_status"]
          total_experience_months: number | null
          updated_at: string
        }
        Insert: {
          about?: string | null
          allow_invitations?: boolean
          allow_recruiter_requests?: boolean
          category_id?: string | null
          completeness_score?: number
          created_at?: string
          discoverability?: Database["public"]["Enums"]["discoverability"]
          headline?: string | null
          id?: string
          identity_embedding?: string | null
          is_primary?: boolean
          label: string
          person_id: string
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"]
          status?: Database["public"]["Enums"]["work_identity_status"]
          total_experience_months?: number | null
          updated_at?: string
        }
        Update: {
          about?: string | null
          allow_invitations?: boolean
          allow_recruiter_requests?: boolean
          category_id?: string | null
          completeness_score?: number
          created_at?: string
          discoverability?: Database["public"]["Enums"]["discoverability"]
          headline?: string | null
          id?: string
          identity_embedding?: string | null
          is_primary?: boolean
          label?: string
          person_id?: string
          profession_id?: string | null
          profession_source?: Database["public"]["Enums"]["source_type"]
          status?: Database["public"]["Enums"]["work_identity_status"]
          total_experience_months?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_identities_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "job_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_identities_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_identities_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
        ]
      }
      workforce_events: {
        Row: {
          actor_id: string | null
          after: Json | null
          before: Json | null
          company_id: string | null
          entity_id: string
          entity_type: string
          event: string
          id: number
          occurred_at: string
          person_id: string | null
          reason: string | null
        }
        Insert: {
          actor_id?: string | null
          after?: Json | null
          before?: Json | null
          company_id?: string | null
          entity_id: string
          entity_type: string
          event: string
          id?: never
          occurred_at?: string
          person_id?: string | null
          reason?: string | null
        }
        Update: {
          actor_id?: string | null
          after?: Json | null
          before?: Json | null
          company_id?: string | null
          entity_id?: string
          entity_type?: string
          event?: string
          id?: never
          occurred_at?: string
          person_id?: string | null
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "workforce_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_events_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      workforce_jobs: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          errors: Json
          failed: number
          finished_at: string | null
          id: string
          kind: string
          payload: Json
          processed: number
          started_at: string | null
          status: string
          succeeded: number
          total: number
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          errors?: Json
          failed?: number
          finished_at?: string | null
          id?: string
          kind: string
          payload: Json
          processed?: number
          started_at?: string | null
          status?: string
          succeeded?: number
          total?: number
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          errors?: Json
          failed?: number
          finished_at?: string | null
          id?: string
          kind?: string
          payload?: Json
          processed?: number
          started_at?: string | null
          status?: string
          succeeded?: number
          total?: number
        }
        Relationships: [
          {
            foreignKeyName: "workforce_jobs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_jobs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      workforce_requirements: {
        Row: {
          check_in_method: string
          client_id: string | null
          company_id: string
          country_code: string | null
          created_at: string
          created_by: string | null
          currency: string
          employment_type: string
          end_date: string | null
          geofence_radius_m: number | null
          hours_per_week: number | null
          id: string
          job_id: string | null
          job_order_id: string | null
          late_grace_minutes: number
          location_id: string | null
          location_text: string | null
          notes: string | null
          openings: number
          overtime_policy_id: string | null
          pay_frequency: string
          pay_period: Database["public"]["Enums"]["pay_period"] | null
          pay_rate: number | null
          profession_id: string | null
          site_name: string | null
          start_date: string | null
          status: string
          supervisor_id: string | null
          timezone: string
          title: string
          updated_at: string
          work_type: Database["public"]["Enums"]["work_type"]
        }
        Insert: {
          check_in_method?: string
          client_id?: string | null
          company_id: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency: string
          employment_type?: string
          end_date?: string | null
          geofence_radius_m?: number | null
          hours_per_week?: number | null
          id?: string
          job_id?: string | null
          job_order_id?: string | null
          late_grace_minutes?: number
          location_id?: string | null
          location_text?: string | null
          notes?: string | null
          openings?: number
          overtime_policy_id?: string | null
          pay_frequency?: string
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          pay_rate?: number | null
          profession_id?: string | null
          site_name?: string | null
          start_date?: string | null
          status?: string
          supervisor_id?: string | null
          timezone?: string
          title: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"]
        }
        Update: {
          check_in_method?: string
          client_id?: string | null
          company_id?: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          employment_type?: string
          end_date?: string | null
          geofence_radius_m?: number | null
          hours_per_week?: number | null
          id?: string
          job_id?: string | null
          job_order_id?: string | null
          late_grace_minutes?: number
          location_id?: string | null
          location_text?: string | null
          notes?: string | null
          openings?: number
          overtime_policy_id?: string | null
          pay_frequency?: string
          pay_period?: Database["public"]["Enums"]["pay_period"] | null
          pay_rate?: number | null
          profession_id?: string | null
          site_name?: string | null
          start_date?: string | null
          status?: string
          supervisor_id?: string | null
          timezone?: string
          title?: string
          updated_at?: string
          work_type?: Database["public"]["Enums"]["work_type"]
        }
        Relationships: [
          {
            foreignKeyName: "workforce_requirements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "agency_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_country_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "country_policies"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "workforce_requirements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_currency_currency_fk"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "workforce_requirements_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_job_order_id_fkey"
            columns: ["job_order_id"]
            isOneToOne: false
            referencedRelation: "job_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_overtime_policy_id_fkey"
            columns: ["overtime_policy_id"]
            isOneToOne: false
            referencedRelation: "overtime_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_profession_id_fkey"
            columns: ["profession_id"]
            isOneToOne: false
            referencedRelation: "professions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workforce_requirements_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      omelo_accept_team_invitation: {
        Args: { p_invitation: string }
        Returns: string
      }
      omelo_add_earning_adjustment: {
        Args: { p_amount: number; p_earning: string; p_reason: string }
        Returns: undefined
      }
      omelo_add_timesheet_entry: {
        Args: {
          p_minutes: number
          p_note: string
          p_timesheet: string
          p_work_date: string
        }
        Returns: string
      }
      omelo_admin_add_exchange_rate: {
        Args: {
          p_base: string
          p_effective_at: string
          p_quote: string
          p_rate: number
          p_source: string
        }
        Returns: number
      }
      omelo_admin_kpis: { Args: { p_days?: number }; Returns: Json }
      omelo_admin_matching_metrics: { Args: { p_days?: number }; Returns: Json }
      omelo_admin_set_company_verification: {
        Args: { p_company: string; p_method?: string; p_verified: boolean }
        Returns: undefined
      }
      omelo_admin_set_entitlements: {
        Args: {
          p_company: string
          p_outreach_quota_daily?: number
          p_plan: string
          p_search_quota_monthly?: number
          p_talent_search: boolean
          p_valid_until?: string
        }
        Returns: undefined
      }
      omelo_admin_system_health: { Args: { p_hours?: number }; Returns: Json }
      omelo_agency_candidates: {
        Args: { p_agency: string; p_job_order?: string }
        Returns: Json
      }
      omelo_agency_dashboard: { Args: { p_agency: string }; Returns: Json }
      omelo_agency_submissions: {
        Args: { p_agency: string; p_job_order?: string }
        Returns: Json
      }
      omelo_am_i_platform_admin: { Args: never; Returns: boolean }
      omelo_approve_earnings: {
        Args: { p_earning: string }
        Returns: undefined
      }
      omelo_archive_work_identity: {
        Args: { p_archive?: boolean; p_identity: string }
        Returns: undefined
      }
      omelo_assign_job_order_recruiter: {
        Args: {
          p_assign?: boolean
          p_order: string
          p_person: string
          p_role?: string
        }
        Returns: undefined
      }
      omelo_assign_shift: {
        Args: { p_assignments: string[]; p_shift: string }
        Returns: Json
      }
      omelo_build_timesheet: {
        Args: {
          p_assignment: string
          p_period_end: string
          p_period_start: string
        }
        Returns: string
      }
      omelo_cancel_account_deletion: { Args: never; Returns: boolean }
      omelo_cancel_interview: {
        Args: { p_interview_id: string; p_reason: string }
        Returns: undefined
      }
      omelo_cancel_leave: { Args: { p_leave: string }; Returns: undefined }
      omelo_cancel_shift: {
        Args: { p_reason: string; p_shift: string }
        Returns: undefined
      }
      omelo_cancel_workforce_job: {
        Args: { p_job: string }
        Returns: undefined
      }
      omelo_candidate_eligibility: {
        Args: { p_identity: string; p_job: string }
        Returns: Json
      }
      omelo_check_in: {
        Args: {
          p_code?: string
          p_lat?: number
          p_lng?: number
          p_method?: string
          p_shift_worker: string
        }
        Returns: string
      }
      omelo_check_out: {
        Args: { p_lat?: number; p_lng?: number; p_shift_worker: string }
        Returns: Json
      }
      omelo_client_job_orders: { Args: never; Returns: Json }
      omelo_client_submissions: { Args: { p_job_id?: string }; Returns: Json }
      omelo_client_workforce: { Args: { p_company: string }; Returns: Json }
      omelo_comms_claim: {
        Args: { p_limit?: number }
        Returns: {
          attempts: number
          channel: string
          created_at: string
          dedupe_key: string | null
          id: string
          last_error: string | null
          payload: Json
          person_id: string | null
          provider_message_id: string | null
          send_after: string
          sent_at: string | null
          status: string
          subject: string | null
          template: string
          to_address: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "outbound_messages"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      omelo_comms_mark: {
        Args: {
          p_error?: string
          p_id: string
          p_ok: boolean
          p_provider_id?: string
        }
        Returns: undefined
      }
      omelo_company_slug: { Args: { p_name: string }; Returns: string }
      omelo_complete_interview: {
        Args: {
          p_concerns?: string
          p_interview_id: string
          p_notes?: string
          p_outcome?: Database["public"]["Enums"]["interview_status"]
          p_rating?: number
          p_recommendation?: string
          p_strengths?: string
        }
        Returns: undefined
      }
      omelo_confirm_interview: {
        Args: { p_interview_id: string }
        Returns: undefined
      }
      omelo_confirm_verification: {
        Args: { p_channel: string; p_code: string }
        Returns: Json
      }
      omelo_consent_candidate: { Args: { p_consent: string }; Returns: Json }
      omelo_convert_currency: {
        Args: { p_amount: number; p_from: string; p_to: string }
        Returns: Json
      }
      omelo_correct_attendance: {
        Args: {
          p_attendance: string
          p_check_in: string
          p_check_out: string
          p_reason: string
        }
        Returns: undefined
      }
      omelo_country_guide: {
        Args: { p_country: string; p_profession?: string }
        Returns: Json
      }
      omelo_create_agency: {
        Args: { p_country?: string; p_independent?: boolean; p_name: string }
        Returns: string
      }
      omelo_create_job_order: {
        Args: { p_client: string; p_order: Json }
        Returns: string
      }
      omelo_create_requirement: {
        Args: { p_company: string; p_fields: Json }
        Returns: string
      }
      omelo_create_shift: {
        Args: { p_requirement: string; p_shift: Json }
        Returns: string
      }
      omelo_create_work_identity: {
        Args: {
          p_copy?: string[]
          p_copy_from?: string
          p_label: string
          p_profession_id?: string
        }
        Returns: string
      }
      omelo_decline_team_invitation: {
        Args: { p_invitation: string }
        Returns: undefined
      }
      omelo_delete_work_identity: {
        Args: { p_identity: string }
        Returns: undefined
      }
      omelo_end_client_link: { Args: { p_client: string }; Returns: undefined }
      omelo_generate_shifts: {
        Args: { p_from: string; p_template: string; p_to: string }
        Returns: number
      }
      omelo_global_jobs: {
        Args: {
          p_filters?: Json
          p_limit?: number
          p_offset?: number
          p_tab?: string
        }
        Returns: Json
      }
      omelo_identity_evidence: { Args: { p_identity: string }; Returns: Json }
      omelo_identity_profile: { Args: { p_identity?: string }; Returns: Json }
      omelo_interview_question_suggestions: {
        Args: { p_job_id: string; p_round_kind?: string }
        Returns: {
          category: string
          id: string
          position: number
          question: string
          rank: number
        }[]
      }
      omelo_invite_team_member: {
        Args: { p_company: string; p_email: string; p_role: string }
        Returns: string
      }
      omelo_invite_to_apply: {
        Args: { p_identity: string; p_job_id: string; p_message?: string }
        Returns: string
      }
      omelo_job_eligibility: {
        Args: { p_identity?: string; p_job: string }
        Returns: Json
      }
      omelo_job_funnel: { Args: { p_job_id: string }; Returns: Json }
      omelo_job_invitations: { Args: { p_job_id: string }; Returns: Json }
      omelo_license_requirements: {
        Args: { p_country?: string; p_profession: string }
        Returns: Json
      }
      omelo_link_job_order: {
        Args: { p_job: string; p_job_order: string }
        Returns: undefined
      }
      omelo_mark_application_viewed: {
        Args: { p_application_id: string }
        Returns: undefined
      }
      omelo_mark_conversation_read: {
        Args: { p_conversation_id: string }
        Returns: number
      }
      omelo_mark_invitation_viewed: {
        Args: { p_invitation: string }
        Returns: undefined
      }
      omelo_meet_admit: {
        Args: { p_admit?: boolean; p_interview_id: string; p_person_id: string }
        Returns: undefined
      }
      omelo_meet_end: { Args: { p_interview_id: string }; Returns: string }
      omelo_meet_join: { Args: { p_room_name: string }; Returns: Json }
      omelo_meet_leave: { Args: { p_interview_id: string }; Returns: undefined }
      omelo_meet_remove: {
        Args: { p_interview_id: string; p_person_id: string; p_reason?: string }
        Returns: string
      }
      omelo_move_application: {
        Args: {
          p_application_id: string
          p_state: Database["public"]["Enums"]["application_state"]
        }
        Returns: Database["public"]["Enums"]["application_state"]
      }
      omelo_my_agency_relationships: { Args: never; Returns: Json }
      omelo_my_assignments: { Args: never; Returns: Json }
      omelo_my_earnings: { Args: never; Returns: Json }
      omelo_my_invitations: { Args: never; Returns: Json }
      omelo_my_match: {
        Args: { p_job_id: string; p_work_identity_id?: string }
        Returns: Json
      }
      omelo_my_mobility: { Args: never; Returns: Json }
      omelo_my_profile_views: { Args: { p_days?: number }; Returns: Json }
      omelo_my_representations: { Args: never; Returns: Json }
      omelo_my_sessions: {
        Args: never
        Returns: {
          created_at: string
          id: string
          ip_hint: string
          is_current: boolean
          last_active_at: string
          user_agent: string
        }[]
      }
      omelo_my_team_invitations: { Args: never; Returns: Json }
      omelo_my_trust_status: { Args: never; Returns: Json }
      omelo_my_work: { Args: { p_from?: string; p_to?: string }; Returns: Json }
      omelo_nearby_jobs: {
        Args: {
          p_category_id?: string
          p_lat: number
          p_limit?: number
          p_lng: number
          p_min_pay_monthly?: number
          p_no_experience?: boolean
          p_offset?: number
          p_radius_km?: number
          p_search?: string
          p_shift_types?: Database["public"]["Enums"]["shift_type"][]
          p_work_types?: Database["public"]["Enums"]["work_type"][]
        }
        Returns: {
          accepts_no_experience: boolean
          benefits: string[]
          category_slug: string
          company_id: string
          company_name: string
          company_response_hours: number
          company_slug: string
          company_verified: boolean
          distance_km: number
          is_immediate_start: boolean
          job_id: string
          job_pay_period: Database["public"]["Enums"]["pay_period"]
          job_work_type: Database["public"]["Enums"]["work_type"]
          job_workplace: Database["public"]["Enums"]["workplace_type"]
          location_text: string
          min_experience_months: number
          openings: number
          pay_currency: string
          pay_max: number
          pay_min: number
          pay_monthly_min: number
          pay_negotiable: boolean
          profession_name: string
          published_at: string
          quick_apply_enabled: boolean
          shift_types: Database["public"]["Enums"]["shift_type"][]
          title: string
        }[]
      }
      omelo_normalized_pay: {
        Args: {
          p_amount: number
          p_currency: string
          p_period: Database["public"]["Enums"]["pay_period"]
          p_target?: string
        }
        Returns: Json
      }
      omelo_offer_assignment: {
        Args: { p_fields?: Json; p_identity: string; p_requirement: string }
        Returns: string
      }
      omelo_offer_shift: {
        Args: { p_assignments: string[]; p_shift: string }
        Returns: Json
      }
      omelo_pay_monthly: {
        Args: {
          p_amount: number
          p_country?: string
          p_period: Database["public"]["Enums"]["pay_period"]
        }
        Returns: number
      }
      omelo_pool_members: { Args: { p_pool: string }; Returns: Json }
      omelo_profile_schema_for: {
        Args: { p_work_identity_id?: string }
        Returns: {
          attribute_id: string
          data_type: Database["public"]["Enums"]["attribute_data_type"]
          help_text: string
          is_required: boolean
          label: string
          options: Json
          scope: string
          slug: string
          sort_position: number
        }[]
      }
      omelo_rank_applicants: {
        Args: { p_job_id: string }
        Returns: {
          application_id: string
          eligible: boolean
          score: number
        }[]
      }
      omelo_recommend_jobs: {
        Args: {
          p_lat: number
          p_limit?: number
          p_lng: number
          p_radius_km?: number
          p_work_identity_id?: string
        }
        Returns: {
          distance_km: number
          eligible: boolean
          gaps: Json
          job_id: string
          score: number
          strengths: Json
        }[]
      }
      omelo_record_attendance: {
        Args: {
          p_check_in: string
          p_check_out?: string
          p_note?: string
          p_shift_worker: string
        }
        Returns: string
      }
      omelo_record_payment: {
        Args: {
          p_amount: number
          p_earning: string
          p_provider?: string
          p_reference?: string
          p_scheduled_for?: string
          p_status?: string
        }
        Returns: string
      }
      omelo_record_submission_outcome: {
        Args: {
          p_note?: string
          p_start_date?: string
          p_status: string
          p_submission: string
        }
        Returns: undefined
      }
      omelo_reject_application: {
        Args: { p_application_id: string; p_reason: string }
        Returns: undefined
      }
      omelo_remove_pay_component: {
        Args: { p_component: string }
        Returns: undefined
      }
      omelo_remove_timesheet_entry: {
        Args: { p_entry: string }
        Returns: undefined
      }
      omelo_reopen_timesheet: {
        Args: { p_reason: string; p_timesheet: string }
        Returns: undefined
      }
      omelo_report_meet_abuse: {
        Args: {
          p_details?: string
          p_interview_id: string
          p_reason: string
          p_reported_person_id?: string
        }
        Returns: string
      }
      omelo_request_account_deletion: {
        Args: { p_reason?: string }
        Returns: Json
      }
      omelo_request_client_link: {
        Args: { p_client: string; p_company: string }
        Returns: undefined
      }
      omelo_request_email_verification: { Args: never; Returns: Json }
      omelo_request_leave: {
        Args: {
          p_assignment: string
          p_end: string
          p_label?: string
          p_reason?: string
          p_start: string
          p_type: string
        }
        Returns: string
      }
      omelo_request_phone_verification: {
        Args: { p_phone: string }
        Returns: Json
      }
      omelo_request_representation: {
        Args: {
          p_identity: string
          p_job_order: string
          p_message?: string
          p_scope?: string[]
          p_valid_days?: number
        }
        Returns: string
      }
      omelo_reschedule_interview: {
        Args: {
          p_duration_minutes?: number
          p_interview_id: string
          p_reason?: string
          p_scheduled_at: string
        }
        Returns: undefined
      }
      omelo_respond_client_link: {
        Args: { p_accept: boolean; p_client: string }
        Returns: undefined
      }
      omelo_respond_to_assignment: {
        Args: { p_accept: boolean; p_assignment: string; p_reason?: string }
        Returns: string
      }
      omelo_respond_to_invitation: {
        Args: { p_invitation: string; p_reason?: string }
        Returns: undefined
      }
      omelo_respond_to_offer: {
        Args: { p_accept: boolean; p_offer_id: string; p_reason?: string }
        Returns: Json
      }
      omelo_respond_to_representation: {
        Args: { p_accept: boolean; p_consent: string; p_reason?: string }
        Returns: undefined
      }
      omelo_respond_to_shift: {
        Args: { p_accept: boolean; p_shift_worker: string }
        Returns: string
      }
      omelo_review_attendance: {
        Args: {
          p_attendance: string
          p_break_minutes?: number
          p_check_in?: string
          p_check_out?: string
          p_decision: string
          p_note?: string
        }
        Returns: undefined
      }
      omelo_review_leave: {
        Args: { p_approve: boolean; p_leave: string; p_note?: string }
        Returns: undefined
      }
      omelo_review_timesheet: {
        Args: { p_approve: boolean; p_reason?: string; p_timesheet: string }
        Returns: Json
      }
      omelo_revoke_other_sessions: { Args: never; Returns: number }
      omelo_revoke_representation: {
        Args: { p_consent: string; p_reason?: string }
        Returns: undefined
      }
      omelo_revoke_session: { Args: { p_session_id: string }; Returns: boolean }
      omelo_save_identity_profile: {
        Args: { p_identity: string; p_values: Json }
        Returns: Json
      }
      omelo_save_interview_feedback: {
        Args: {
          p_answers?: Json
          p_competencies?: Json
          p_concerns?: string
          p_interview_id: string
          p_notes?: string
          p_rating?: number
          p_recommendation?: string
          p_skills?: Json
          p_strengths?: string
          p_submit?: boolean
        }
        Returns: string
      }
      omelo_save_mobility: { Args: { p: Json }; Returns: Json }
      omelo_save_pay_component: {
        Args: {
          p_amount: number
          p_assignment: string
          p_basis: string
          p_kind: string
          p_name: string
          p_requirement: string
          p_shift_types?: string[]
        }
        Returns: string
      }
      omelo_save_shift_template: {
        Args: {
          p_requirement: string
          p_template: Json
          p_template_id?: string
        }
        Returns: string
      }
      omelo_schedule_interview: {
        Args: {
          p_application_id: string
          p_duration_minutes?: number
          p_instructions?: string
          p_interviewer_ids?: string[]
          p_location_text?: string
          p_meeting_mode?: string
          p_questions?: Json
          p_round_kind?: string
          p_round_name?: string
          p_scheduled_at: string
          p_send_email?: boolean
          p_send_notification?: boolean
          p_timezone?: string
        }
        Returns: string
      }
      omelo_search_talent: {
        Args: {
          p_filters?: Json
          p_job_id: string
          p_limit?: number
          p_offset?: number
          p_query?: string
          p_radius_km?: number
        }
        Returns: Json
      }
      omelo_search_talent_for_order: {
        Args: {
          p_filters?: Json
          p_job_order: string
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      omelo_send_message: {
        Args: { p_body: string; p_conversation_id: string }
        Returns: number
      }
      omelo_send_offer: {
        Args: {
          p_application_id: string
          p_benefits?: Json
          p_conditions?: string
          p_expires_at?: string
          p_pay_amount: number
          p_pay_period: Database["public"]["Enums"]["pay_period"]
          p_start_date: string
          p_title?: string
        }
        Returns: string
      }
      omelo_set_assignment_billing: {
        Args: {
          p_assignment: string
          p_bill_period: string
          p_bill_rate: number
          p_note?: string
        }
        Returns: undefined
      }
      omelo_set_assignment_status: {
        Args: {
          p_assignment: string
          p_end_date?: string
          p_reason?: string
          p_status: string
        }
        Returns: undefined
      }
      omelo_set_primary_identity: {
        Args: { p_identity: string }
        Returns: undefined
      }
      omelo_shift_replacements: { Args: { p_shift: string }; Returns: Json }
      omelo_shift_roster: { Args: { p_shift: string }; Returns: Json }
      omelo_start_conversation: {
        Args: { p_application_id: string }
        Returns: string
      }
      omelo_start_timesheet_review: {
        Args: { p_timesheet: string }
        Returns: undefined
      }
      omelo_start_workforce_job: {
        Args: { p_company: string; p_kind: string; p_payload: Json }
        Returns: string
      }
      omelo_submit_candidate: {
        Args: { p_consent: string; p_note?: string }
        Returns: string
      }
      omelo_submit_timesheet: {
        Args: { p_timesheet: string }
        Returns: undefined
      }
      omelo_talent_profile: {
        Args: { p_identity: string; p_job_id?: string }
        Returns: Json
      }
      omelo_track_job_events: { Args: { p_events: Json }; Returns: number }
      omelo_unassign_shift: {
        Args: { p_reason?: string; p_shift_worker: string }
        Returns: undefined
      }
      omelo_update_billing_status: {
        Args: { p_billing: string; p_status: string }
        Returns: undefined
      }
      omelo_update_job_order: {
        Args: { p_changes: Json; p_order: string }
        Returns: undefined
      }
      omelo_update_payment: {
        Args: {
          p_failure_reason?: string
          p_payment: string
          p_reference?: string
          p_status: string
        }
        Returns: undefined
      }
      omelo_update_placement: {
        Args: { p_changes: Json; p_placement: string }
        Returns: undefined
      }
      omelo_update_requirement: {
        Args: { p_changes: Json; p_requirement: string }
        Returns: undefined
      }
      omelo_update_shift: {
        Args: { p_changes: Json; p_shift: string }
        Returns: undefined
      }
      omelo_view_offer: { Args: { p_offer_id: string }; Returns: undefined }
      omelo_withdraw_application: {
        Args: { p_application_id: string; p_reason?: string }
        Returns: undefined
      }
      omelo_withdraw_invitation: {
        Args: { p_invitation: string }
        Returns: undefined
      }
      omelo_withdraw_offer: {
        Args: { p_offer_id: string; p_reason: string }
        Returns: undefined
      }
      omelo_withdraw_representation_request: {
        Args: { p_consent: string }
        Returns: undefined
      }
      omelo_withdraw_submission: {
        Args: { p_reason?: string; p_submission: string }
        Returns: undefined
      }
      omelo_workforce_approvals: { Args: { p_company: string }; Returns: Json }
      omelo_workforce_dashboard: { Args: { p_company: string }; Returns: Json }
    }
    Enums: {
      actor_type: "candidate" | "recruiter" | "system" | "admin"
      application_event_type:
        | "created"
        | "viewed"
        | "stage_changed"
        | "shortlisted"
        | "message_sent"
        | "note_added"
        | "document_requested"
        | "document_shared"
        | "interview_scheduled"
        | "interview_completed"
        | "assessment_sent"
        | "assessment_completed"
        | "offer_extended"
        | "offer_responded"
        | "decision_made"
        | "withdrawn"
        | "expired"
      application_state:
        | "applied"
        | "viewed"
        | "shortlisted"
        | "screening"
        | "assessment"
        | "interview"
        | "offer"
        | "hired"
        | "rejected"
        | "withdrawn"
        | "expired"
        | "declined_by_candidate"
      attribute_data_type:
        | "text"
        | "long_text"
        | "number"
        | "boolean"
        | "single_select"
        | "multi_select"
        | "date"
        | "years"
        | "file"
        | "location"
      availability_window:
        | "immediate"
        | "within_7_days"
        | "within_15_days"
        | "within_30_days"
        | "within_60_days"
        | "within_90_days"
        | "flexible"
        | "not_available"
      benefit_type:
        | "accommodation"
        | "transport"
        | "meals"
        | "health_insurance"
        | "life_insurance"
        | "visa_sponsorship"
        | "flight_tickets"
        | "relocation_assistance"
        | "bonus"
        | "overtime_pay"
        | "tips"
        | "commission"
        | "paid_leave"
        | "sick_leave"
        | "parental_leave"
        | "training"
        | "equipment_provided"
        | "uniform_provided"
        | "childcare"
        | "retirement"
        | "stock_options"
        | "gym"
        | "other"
      company_role:
        | "owner"
        | "admin"
        | "recruiter"
        | "hiring_manager"
        | "interviewer"
        | "hr"
        | "finance"
        | "viewer"
        | "sourcer"
        | "coordinator"
      company_size_band:
        | "1-10"
        | "11-50"
        | "51-200"
        | "201-500"
        | "501-1000"
        | "1001-5000"
        | "5001-10000"
        | "10000+"
      discoverability:
        | "private"
        | "matched_only"
        | "discoverable"
        | "recruiters"
        | "public"
      document_type:
        | "resume"
        | "cover_letter"
        | "government_id"
        | "passport"
        | "work_permit"
        | "driving_license"
        | "trade_license"
        | "professional_license"
        | "education_certificate"
        | "professional_certificate"
        | "experience_letter"
        | "payslip"
        | "portfolio"
        | "police_clearance"
        | "medical_certificate"
        | "photo"
        | "reference_letter"
        | "other"
      education_level:
        | "none"
        | "primary"
        | "secondary"
        | "high_school"
        | "vocational"
        | "certificate"
        | "diploma"
        | "associate"
        | "bachelor"
        | "master"
        | "doctorate"
        | "professional"
        | "other"
      employment_status: "active" | "on_notice" | "ended" | "terminated"
      evidence_type:
        | "self_declared"
        | "experience"
        | "project"
        | "credential"
        | "license"
        | "assessment"
        | "employer_verified"
        | "reference"
      interview_recommendation: "reject" | "hold" | "advance" | "strong_advance"
      interview_status:
        | "scheduled"
        | "rescheduled"
        | "completed"
        | "cancelled"
        | "no_show_candidate"
        | "no_show_employer"
      interview_type:
        | "phone"
        | "video"
        | "in_person"
        | "group"
        | "walk_in"
        | "trial_shift"
        | "practical_test"
        | "assessment_centre"
        | "panel"
      job_status:
        | "draft"
        | "pending_review"
        | "published"
        | "paused"
        | "expired"
        | "closed"
        | "rejected"
      language_proficiency:
        | "basic"
        | "conversational"
        | "professional"
        | "fluent"
        | "native"
      message_kind: "text" | "action" | "attachment" | "system"
      moderation_action:
        | "none"
        | "warning"
        | "content_removed"
        | "job_unpublished"
        | "account_suspended"
        | "account_banned"
        | "verification_revoked"
      notification_type:
        | "job_match"
        | "job_alert"
        | "saved_search"
        | "application_update"
        | "recruiter_message"
        | "interview_scheduled"
        | "interview_reminder"
        | "offer_received"
        | "document_request"
        | "verification_update"
        | "career_recommendation"
        | "company_update"
        | "job_closing_soon"
        | "profile_reminder"
        | "system"
        | "message_received"
        | "job_invitation"
        | "representation_request"
        | "representation_update"
        | "shift_update"
        | "work_update"
      offer_status:
        | "draft"
        | "sent"
        | "viewed"
        | "negotiating"
        | "accepted"
        | "declined"
        | "withdrawn"
        | "expired"
      pay_basis: "gross" | "net"
      pay_period:
        | "hour"
        | "day"
        | "week"
        | "fortnight"
        | "month"
        | "year"
        | "per_task"
      proficiency_level:
        | "beginner"
        | "basic"
        | "intermediate"
        | "advanced"
        | "expert"
      relation_kind:
        | "adjacent_to"
        | "prerequisite_of"
        | "substitutable_for"
        | "specialisation_of"
      report_reason:
        | "fraud"
        | "payment_request"
        | "discrimination"
        | "harassment"
        | "misleading_job"
        | "fake_company"
        | "spam"
        | "inappropriate_content"
        | "data_misuse"
        | "other"
      report_status:
        | "open"
        | "triaging"
        | "actioned"
        | "dismissed"
        | "escalated"
      requirement_level: "required" | "preferred" | "nice_to_have"
      shift_type:
        | "day"
        | "evening"
        | "night"
        | "early_morning"
        | "rotating"
        | "split"
        | "flexible"
        | "weekend"
        | "on_call"
      skill_type:
        | "technical"
        | "tool"
        | "equipment"
        | "trade"
        | "physical"
        | "domain"
        | "method"
        | "soft"
        | "language"
        | "safety"
        | "administrative"
      source_type:
        | "user"
        | "import"
        | "inference"
        | "admin"
        | "partner"
        | "employer"
      taxonomy_status: "active" | "pending_review" | "deprecated" | "merged"
      verification_method:
        | "otp"
        | "domain_email"
        | "employer_confirmation"
        | "document_review"
        | "issuer_api"
        | "institution_partner"
        | "government_api"
        | "third_party_provider"
        | "manual_admin"
      verification_status:
        | "unverified"
        | "pending"
        | "verified"
        | "failed"
        | "expired"
        | "revoked"
      verification_type:
        | "identity"
        | "phone"
        | "email"
        | "address"
        | "education"
        | "employment"
        | "license"
        | "certificate"
        | "right_to_work"
        | "background_check"
        | "reference"
      work_auth_status:
        | "citizen"
        | "permanent_resident"
        | "work_permit"
        | "dependent_visa_work_rights"
        | "student_visa_limited"
        | "requires_sponsorship"
        | "no_right_to_work"
        | "employer_sponsored"
        | "other_authorization"
        | "unknown"
      work_identity_status: "active" | "paused" | "archived"
      work_type:
        | "full_time"
        | "part_time"
        | "contract"
        | "freelance"
        | "temporary"
        | "internship"
        | "apprenticeship"
        | "seasonal"
        | "gig"
        | "volunteer"
        | "daily_wage"
      workplace_type:
        | "onsite"
        | "hybrid"
        | "remote"
        | "field_based"
        | "client_site"
        | "multiple_sites"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      actor_type: ["candidate", "recruiter", "system", "admin"],
      application_event_type: [
        "created",
        "viewed",
        "stage_changed",
        "shortlisted",
        "message_sent",
        "note_added",
        "document_requested",
        "document_shared",
        "interview_scheduled",
        "interview_completed",
        "assessment_sent",
        "assessment_completed",
        "offer_extended",
        "offer_responded",
        "decision_made",
        "withdrawn",
        "expired",
      ],
      application_state: [
        "applied",
        "viewed",
        "shortlisted",
        "screening",
        "assessment",
        "interview",
        "offer",
        "hired",
        "rejected",
        "withdrawn",
        "expired",
        "declined_by_candidate",
      ],
      attribute_data_type: [
        "text",
        "long_text",
        "number",
        "boolean",
        "single_select",
        "multi_select",
        "date",
        "years",
        "file",
        "location",
      ],
      availability_window: [
        "immediate",
        "within_7_days",
        "within_15_days",
        "within_30_days",
        "within_60_days",
        "within_90_days",
        "flexible",
        "not_available",
      ],
      benefit_type: [
        "accommodation",
        "transport",
        "meals",
        "health_insurance",
        "life_insurance",
        "visa_sponsorship",
        "flight_tickets",
        "relocation_assistance",
        "bonus",
        "overtime_pay",
        "tips",
        "commission",
        "paid_leave",
        "sick_leave",
        "parental_leave",
        "training",
        "equipment_provided",
        "uniform_provided",
        "childcare",
        "retirement",
        "stock_options",
        "gym",
        "other",
      ],
      company_role: [
        "owner",
        "admin",
        "recruiter",
        "hiring_manager",
        "interviewer",
        "hr",
        "finance",
        "viewer",
        "sourcer",
        "coordinator",
      ],
      company_size_band: [
        "1-10",
        "11-50",
        "51-200",
        "201-500",
        "501-1000",
        "1001-5000",
        "5001-10000",
        "10000+",
      ],
      discoverability: [
        "private",
        "matched_only",
        "discoverable",
        "recruiters",
        "public",
      ],
      document_type: [
        "resume",
        "cover_letter",
        "government_id",
        "passport",
        "work_permit",
        "driving_license",
        "trade_license",
        "professional_license",
        "education_certificate",
        "professional_certificate",
        "experience_letter",
        "payslip",
        "portfolio",
        "police_clearance",
        "medical_certificate",
        "photo",
        "reference_letter",
        "other",
      ],
      education_level: [
        "none",
        "primary",
        "secondary",
        "high_school",
        "vocational",
        "certificate",
        "diploma",
        "associate",
        "bachelor",
        "master",
        "doctorate",
        "professional",
        "other",
      ],
      employment_status: ["active", "on_notice", "ended", "terminated"],
      evidence_type: [
        "self_declared",
        "experience",
        "project",
        "credential",
        "license",
        "assessment",
        "employer_verified",
        "reference",
      ],
      interview_recommendation: ["reject", "hold", "advance", "strong_advance"],
      interview_status: [
        "scheduled",
        "rescheduled",
        "completed",
        "cancelled",
        "no_show_candidate",
        "no_show_employer",
      ],
      interview_type: [
        "phone",
        "video",
        "in_person",
        "group",
        "walk_in",
        "trial_shift",
        "practical_test",
        "assessment_centre",
        "panel",
      ],
      job_status: [
        "draft",
        "pending_review",
        "published",
        "paused",
        "expired",
        "closed",
        "rejected",
      ],
      language_proficiency: [
        "basic",
        "conversational",
        "professional",
        "fluent",
        "native",
      ],
      message_kind: ["text", "action", "attachment", "system"],
      moderation_action: [
        "none",
        "warning",
        "content_removed",
        "job_unpublished",
        "account_suspended",
        "account_banned",
        "verification_revoked",
      ],
      notification_type: [
        "job_match",
        "job_alert",
        "saved_search",
        "application_update",
        "recruiter_message",
        "interview_scheduled",
        "interview_reminder",
        "offer_received",
        "document_request",
        "verification_update",
        "career_recommendation",
        "company_update",
        "job_closing_soon",
        "profile_reminder",
        "system",
        "message_received",
        "job_invitation",
        "representation_request",
        "representation_update",
        "shift_update",
        "work_update",
      ],
      offer_status: [
        "draft",
        "sent",
        "viewed",
        "negotiating",
        "accepted",
        "declined",
        "withdrawn",
        "expired",
      ],
      pay_basis: ["gross", "net"],
      pay_period: [
        "hour",
        "day",
        "week",
        "fortnight",
        "month",
        "year",
        "per_task",
      ],
      proficiency_level: [
        "beginner",
        "basic",
        "intermediate",
        "advanced",
        "expert",
      ],
      relation_kind: [
        "adjacent_to",
        "prerequisite_of",
        "substitutable_for",
        "specialisation_of",
      ],
      report_reason: [
        "fraud",
        "payment_request",
        "discrimination",
        "harassment",
        "misleading_job",
        "fake_company",
        "spam",
        "inappropriate_content",
        "data_misuse",
        "other",
      ],
      report_status: ["open", "triaging", "actioned", "dismissed", "escalated"],
      requirement_level: ["required", "preferred", "nice_to_have"],
      shift_type: [
        "day",
        "evening",
        "night",
        "early_morning",
        "rotating",
        "split",
        "flexible",
        "weekend",
        "on_call",
      ],
      skill_type: [
        "technical",
        "tool",
        "equipment",
        "trade",
        "physical",
        "domain",
        "method",
        "soft",
        "language",
        "safety",
        "administrative",
      ],
      source_type: [
        "user",
        "import",
        "inference",
        "admin",
        "partner",
        "employer",
      ],
      taxonomy_status: ["active", "pending_review", "deprecated", "merged"],
      verification_method: [
        "otp",
        "domain_email",
        "employer_confirmation",
        "document_review",
        "issuer_api",
        "institution_partner",
        "government_api",
        "third_party_provider",
        "manual_admin",
      ],
      verification_status: [
        "unverified",
        "pending",
        "verified",
        "failed",
        "expired",
        "revoked",
      ],
      verification_type: [
        "identity",
        "phone",
        "email",
        "address",
        "education",
        "employment",
        "license",
        "certificate",
        "right_to_work",
        "background_check",
        "reference",
      ],
      work_auth_status: [
        "citizen",
        "permanent_resident",
        "work_permit",
        "dependent_visa_work_rights",
        "student_visa_limited",
        "requires_sponsorship",
        "no_right_to_work",
        "employer_sponsored",
        "other_authorization",
        "unknown",
      ],
      work_identity_status: ["active", "paused", "archived"],
      work_type: [
        "full_time",
        "part_time",
        "contract",
        "freelance",
        "temporary",
        "internship",
        "apprenticeship",
        "seasonal",
        "gig",
        "volunteer",
        "daily_wage",
      ],
      workplace_type: [
        "onsite",
        "hybrid",
        "remote",
        "field_based",
        "client_site",
        "multiple_sites",
      ],
    },
  },
} as const
