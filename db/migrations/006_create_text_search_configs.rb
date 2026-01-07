Sequel.migration do
  up do
    create_table :text_search_configs do
      String :language_code, primary_key: true
      String :config_name, null: false
      TrueClass :is_installed, default: true
    end

    # Add index for config name lookup
    add_index :text_search_configs, :config_name

    # Seed initial language configurations
    # Note: These assume pg_jieba extension is installed for Chinese support
    from(:text_search_configs).multi_insert(
      [
        { language_code: 'en', config_name: 'pg_catalog.english' },
        { language_code: 'zh', config_name: 'jiebacfg' },
        { language_code: 'ja', config_name: 'pg_catalog.simple' },
        { language_code: 'ko', config_name: 'pg_catalog.simple' },
        { language_code: 'default', config_name: 'pg_catalog.simple' }
      ]
    )
  end

  down do
    drop_table :text_search_configs
  end
end
