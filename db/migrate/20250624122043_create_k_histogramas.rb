class CreateKHistogramas < ActiveRecord::Migration[7.2]
  def change
    create_table :k_histogramas do |t|
      t.integer :posicao
      t.string :nome_classe
      t.string :contagem

      t.timestamps
    end
  end
end
