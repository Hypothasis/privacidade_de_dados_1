# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_06_23_231951) do
  create_table "l_histogramas", force: :cascade do |t|
    t.integer "data_1"
    t.integer "data_2"
    t.integer "data_3"
    t.integer "data_4"
    t.integer "data_5"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "statistics", force: :cascade do |t|
    t.integer "k"
    t.integer "l"
    t.float "precisao"
    t.integer "classes_geradas"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "top_cidades", force: :cascade do |t|
    t.string "nome_cidade"
    t.integer "contagem"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
