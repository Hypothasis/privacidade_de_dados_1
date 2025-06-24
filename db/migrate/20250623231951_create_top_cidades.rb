class CreateTopCidades < ActiveRecord::Migration[7.2]
  def change
    create_table :top_cidades do |t|
      t.string :nome_cidade
      t.integer :contagem

      t.timestamps
    end
  end
end
